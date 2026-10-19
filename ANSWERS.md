# Capstone Design Review — Operation Zero Downtime (Azure Edition)

> Note: This file mirrors [`terraform/ANSWERS.md`](terraform/ANSWERS.md) at the repository root for convenient grading.

This Azure design adapts the **Operation Zero Downtime** 3-tier capstone for the existing React/Vite + Express + PostgreSQL application. It maps every AWS requirement to its idiomatic Azure equivalent (`VNet`, `NSG` + `ASG`, `Application Gateway Standard_v2`, `Linux VM Scale Set`, `Azure Database for PostgreSQL Flexible Server`, `Azure Blob Storage`, `NAT Gateway`, and optional `Azure Bastion`) while preserving PostgreSQL so the real application runs unmodified.

---

## Milestone 01 — Never Again by Hand (Foundation & Remote State)

### 1. Why is remote state with locking important when working in a team?
Terraform state maps declarative configuration to the real resource IDs deployed in Azure. Storing the state in a shared, access-controlled Azure Blob Storage container (`backend "azurerm"` with Microsoft Entra authentication and blob versioning enabled) ensures that every engineer (e.g., you and Sam) and CI/CD pipeline operates against the exact same source of truth. Native Azure Blob **lease locking** serializes state-mutating operations so that only one `terraform plan`/`apply`/`destroy` can modify a given state key at a time. Blob versioning supports point-in-time state recovery, while Azure RBAC (`Storage Blob Data Contributor`) restricts who can read or mutate state.

### 2. What happens if you and Sam run `terraform apply` at the same time without locking?
Without state locking, both engineers read the same prior state snapshot concurrently and issue conflicting Azure Resource Manager API calls in parallel:
- **Race conditions & duplicate/failed creations:** One apply may fail midway because a resource name or subnet already exists, or both may modify the same NSG/VMSS with conflicting settings.
- **Last-write-wins state corruption:** The second process to finish overwrites the remote `.tfstate` blob, erasing the resource mappings recorded by the first process and leaving orphaned or untracked Azure resources that diverge from Terraform state.

---

## Milestone 02 — Lay the Roads (Networking Module — VNet & Subnets)

### 1. Why do the app servers live in private subnets yet still reach the internet?
The Linux VMSS instances have no public IP addresses attached to their NICs (`snet-*-app`), preventing any direct inbound connection from the internet. However, the app subnet is associated with an Azure **NAT Gateway** (`azurerm_nat_gateway` + static `StandardV2` Public IP). When VMSS instances initiate outbound connections (for example, `apt-get` or NodeSource package downloads during `cloud-init`), the NAT Gateway performs outbound Source Network Address Translation (SNAT). Return packets for established outbound flows are permitted back to the private instances, while unsolicited inbound internet traffic is dropped.

### 2. What is the trade-off between a single NAT Gateway and one per AZ?
- **In AWS:** NAT Gateways are zonal resources. A single NAT Gateway in AZ-a saves roughly half the hourly NAT cost in `dev`, but creates a cross-AZ single point of failure (if AZ-a fails, private subnets in AZ-b lose outbound internet connectivity) and incurs cross-AZ data charges. Provisioning one NAT Gateway per AZ in `prod` eliminates that single point of failure at higher hourly cost.
- **In Azure (this implementation):** Azure subnets are regional (spanning Availability Zones `1` and `2`), and Azure's **`StandardV2` NAT Gateway** SKU is natively **zone-redundant** across the region's Availability Zones. Therefore, a single `StandardV2` NAT Gateway attached to the regional private app subnet provides multi-zone outbound resilience without needing separate per-zone NAT Gateways or per-zone route tables.
- **Database tier isolation:** PostgreSQL Flexible Server sits in its own delegated private subnet (`snet-*-database`) linked to a Private DNS Zone (`*.postgres.database.azure.com`), with `public_network_access_enabled = false` and `default_outbound_access_enabled = false` (no internet route).

---

## Milestone 03 — Locks on Every Door (Security Groups — Least Privilege)

### 1. Why is referencing a security group ID safer than allowing a CIDR range?
Referencing an **Application Security Group (ASG)** ID (`azurerm_application_security_group.api.id` in the `Allow-App-PostgreSQL` rule on `nsg-*-db`) binds access to the logical identity of the workload's network interfaces rather than an IP range:
- **Zero lateral movement from non-API hosts in the same subnet/VNet:** Even if another resource were placed in the VNet, our explicit rule `Deny-Other-VNet-PostgreSQL` blocks `VirtualNetwork` traffic on TCP `5432` unless the source NIC belongs to the `asg-*-api` group.
- **Dynamic auto-scaling:** As the VMSS scales in and out across zones, new instances automatically inherit the `asg-*-api` membership without requiring CIDR recalculations or firewall rule changes.
- *(Note on Application Gateway):* Because Azure Application Gateway v2 uses a dedicated subnet and does not attach to NIC-level ASGs as a traffic source, `nsg-*-app` restricts TCP `5000` strictly to the dedicated `application_gateway_subnet_cidr` (`10.20.4.0/24`), and separate `azurerm_network_security_rule` resources are used instead of inline rules.

### 2. If the Load Balancer (Application Gateway) is compromised, what can an attacker reach directly? Explain using your rules.
- **What is reachable:** From the Application Gateway subnet (`10.20.4.0/24`), `nsg-*-app` only permits inbound **TCP `5000`** to the private app subnet (`10.20.1.0/24`). Therefore, a compromised Application Gateway can only send HTTP requests to port `5000` of the Express/Node.js application on the VMSS instances.
- **What is blocked:**
  - It **cannot SSH (TCP `22`)** into the VMSS instances (`Allow-SSH-From-Bastion` is only created when `enable_bastion = true` and only allows `AzureBastionSubnet`).
  - It **cannot reach PostgreSQL (TCP `5432`)** because `nsg-*-db` only allows TCP `5432` from members of `asg-*-api` and explicitly denies all other `VirtualNetwork` sources (`Deny-Other-VNet-PostgreSQL`).
- *(Defense-in-depth note):* If an attacker subsequently compromised the Node.js process on a VMSS instance, that VM has access to its Entra-linked least-privilege database role (`student_app`), `Storage Blob Data Reader` on the release storage account, and `Storage Blob Data Contributor` on the separate backup storage account. Keeping the DB role non-admin and isolating backups into a dedicated account limits blast radius.

---

## Milestone 04 — Survive the Friday Sale (Load Balancer & Auto-Scaling App Tier)

### 1. What attack does IMDSv2 protect against, and how does Azure handle metadata & passwordless instance access?
- **IMDSv2 protection:** In AWS, IMDSv2 requires a session-oriented `PUT` request with a custom header (`X-aws-ec2-metadata-token-ttl-seconds`) to obtain a token before querying `169.254.169.254`. This mitigates **Server-Side Request Forgery (SSRF)** vulnerabilities where an attacker tricks a web application into making a simple `GET` request to the metadata endpoint to steal temporary IAM role credentials (and prevents container/network-hop credential theft via IP TTL limits).
- **Azure equivalent in this project:** Azure's Instance Metadata Service (`http://169.254.169.254/metadata/identity/oauth2/token`) mandates the custom header **`Metadata: true`** and rejects any request containing `X-Forwarded-For` headers, providing native SSRF defense for the VMSS **System-Assigned Managed Identity**.
- **Operators without SSH:** Inbound SSH is never exposed to the internet. Operators run diagnostics through the Azure control plane using `az vmss run-command invoke` (`scripts/run-vmss-command.sh`), which is the non-interactive Azure equivalent of AWS SSM Run Command.

### 2. What happens to running instances when you change the user data (`custom_data`) and apply with rolling instance refresh enabled?
When `api_release_version` or `cloud-init.sh.tftpl` changes, Terraform updates the `azurerm_linux_virtual_machine_scale_set` model. Because `upgrade_mode = "Rolling"` is configured alongside the `ApplicationHealthLinux` extension (probing `http://localhost:5000/health`) and `rolling_upgrade_policy` (`max_batch_instance_percent = 33`, `pause_time_between_batches = "PT1M"`):
1. Azure upgrades/replaces instances in batches (up to 33% of the fleet at a time) rather than terminating all instances simultaneously.
2. Each upgraded instance boots, runs `cloud-init`, downloads the versioned release ZIP from private Blob Storage via its Managed Identity, starts `student-registration.service`, and must pass `/health` checks before the rolling upgrade advances to the next batch.
3. In `prod` (`min = 2`), healthy instances in the other zone continue serving traffic behind Application Gateway with zero downtime. In `dev` (`initial = 1, min = 1, max = 2`), single-instance baseline means brief interruption can occur unless scaled out first.

---

## Milestone 05 — Guard the Crown Jewels (Data Tier — PostgreSQL & Secure Storage)

### 1. Why is it better to use managed identity / secret manager authentication than to pass a DB password as a Terraform variable?
Passing a password via a Terraform variable exposes the secret in multiple places: local `.tfvars` files, CI environment variables, process arguments, and—most critically—**in plain text inside the Terraform state file (`.tfstate`) and plan files (`.tfplan`)**, where anyone with state read access can extract it.
- **How this Azure project eliminates passwords entirely:** Instead of storing a password in Key Vault or state, `azurerm_postgresql_flexible_server` sets `active_directory_auth_enabled = true` and **`password_auth_enabled = false`**. No database password exists anywhere. The deployment operator authenticates via short-lived Entra OAuth tokens in memory to bootstrap the schema, and the VMSS authenticates at runtime using short-lived tokens acquired by its System-Assigned Managed Identity for the least-privilege `student_app` PostgreSQL role.
- **Storage security:** Both the release storage account (`module.storage`) and backup storage account enforce `https_traffic_only_enabled = true` (Azure equivalent of `aws:SecureTransport = false` deny policy), `min_tls_version = "TLS1_2"`, `allow_nested_items_to_be_public = false`, `shared_access_key_enabled = false`, and blob versioning (`versioning_enabled = true`).

### 2. What does Multi-AZ (Zone-Redundant HA) protect against, and what does it NOT protect against?
- **Protects against:** Physical infrastructure failures in a single Availability Zone (power/cooling/network outage in one datacenter), underlying host hardware failure, or unplanned database compute crashes—automatically failing over to the hot standby in the secondary zone (`standby_availability_zone`).
- **Does NOT protect against:**
  - Human/application errors such as accidental `DROP TABLE`, bad schema migrations, or logical data corruption (which replicate immediately to the standby).
  - Accidental deletion of the Terraform resource or Resource Group (mitigated in `prod` via `azurerm_management_lock` with `CanNotDelete` and pre-destroy `pg_dump` backups via `scripts/backup-postgres-before-destroy.sh`).
  - Full regional Azure outages or compromised application credentials/roles.

---

## Milestone 06 — Launch Day (Environments, Bastion & Production Readiness)

### 1. Workspaces vs separate state keys/directories — which would you use for real production and why?
For real production, **separate state keys (`student-registration/dev.tfstate` vs `student-registration/prod.tfstate` via separate `backend-dev.hcl` and `backend-prod.hcl` configs) or separate state storage accounts/directories** are strongly preferred over `terraform workspace`:
1. **Blast-radius & RBAC isolation:** Separate backend configs allow `dev` and `prod` states to live in different keys, containers, or subscriptions with distinct Azure RBAC permissions (so a developer or PR job with `dev` access cannot read or lock `prod` state).
2. **Preventing human error:** With CLI workspaces, forgetting `terraform workspace select dev` before running `terraform apply` or `destroy` can accidentally hit `prod`. Explicit `-backend-config=backend-dev.hcl` and `-var-file=dev.tfvars` make environment selection explicit and safer for CI/CD automation.

### 2. Which three resources drive most of the cost, and how would you reduce them?
Based on our Azure Retail Prices API analysis (`terraform/docs/cost-estimate-dev-2026-10-19.md`, ~$333.20/month baseline in Central India):
1. **Application Gateway `Standard_v2` (~$262.80/month — $204.40 fixed + $58.40 for 10 CUs):** This is by far the largest cost driver (~79% of dev spend).
   - *How to reduce:* Tear down `dev` after test sessions (`terraform destroy`), set `min_capacity = 0` with autoscale where supported, or in non-production environments replace Application Gateway v2 with a Basic Azure Load Balancer or Azure Container Apps ingress.
2. **NAT Gateway `StandardV2` (~$32.85/month fixed + data processing):**
   - *How to reduce:* Destroy `dev` when idle, and use Service Endpoints / Private Endpoints for Azure Storage so blob downloads do not traverse the NAT Gateway data-processing meter.
3. **PostgreSQL Flexible Server & Linux VMSS Compute (~$22.08/month DB + ~$8.18/month VM in `dev`; scales much higher in `prod` with `GP_Standard_D2s_v3`, Zone-Redundant HA, and 2–6 `Standard_D2s_v5` VMs):**
   - *How to reduce:* Keep `dev` on Burstable SKUs (`B_Standard_B1ms` and `Standard_B2ts_v2`) with `database_high_availability = false` and `api_min_instances = 1`, stop PostgreSQL when not in use, and use 1-year/3-year Azure Reservations or Savings Plans for `prod`.

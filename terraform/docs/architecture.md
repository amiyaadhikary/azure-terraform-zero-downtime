# Azure architecture

```mermaid
flowchart LR
  U[Browser] -->|Public HTTP capstone demo| AGW[Application Gateway Standard_v2]
  AGW -->|all paths| VMSS[Private Linux VM Scale Set :5000, zones 1 and 2]
  VMSS -->|TCP 5432, private DNS| PG[PostgreSQL Flexible Server]
  VMSS -->|system identity, Entra DB token| PG
  VMSS -->|system identity, Blob Data Reader| ART[Private release container]
  VMSS -->|system identity, Blob Data Contributor| BKP[Separate private backup container]
  VMSS -->|outbound package access| NAT[NAT Gateway]
  VMSS -->|health /health| AGW
  VMSS -->|serves React UI and Express API| WEB[Same-origin app]
  NSG[Subnet NSGs and ASGs] -. allow 5000 only from AGW subnet .-> VMSS
  NSG -. allow 5432 only from API ASG; deny other VNet sources .-> PG
```

Application Gateway and VMSS are configured across the `availability_zones` variable (default `1` and `2`). Azure subnets are regional, not AZ-specific; the private app subnet is shared by instances placed in either zone. PostgreSQL uses zone-redundant high availability in the prod profile.

The gateway uses HTTP for the capstone core requirement. HTTPS and redirect are optional bonus work and require a trusted certificate/domain. Authentication has not been added; use synthetic data only. Storage holds Entra-authorized release and backup blobs in separate accounts; the public website is served by the private VMSS behind Application Gateway. PostgreSQL password authentication is disabled; the deployment operator is the Entra administrator and the VMSS identity receives a non-admin database role.

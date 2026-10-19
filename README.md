# Student Registration on Azure

Azure Terraform for the existing React/Vite + Express + PostgreSQL app. It provisions a zonal Application Gateway, private Linux VM Scale Set serving the full app, private PostgreSQL Flexible Server with Entra-only authentication, and private release/backup storage. The VMSS uses a system-assigned Managed Identity for release downloads, backup uploads, and passwordless PostgreSQL access.

```text
Browser -> Application Gateway -> private VMSS (React + Express) -> private PostgreSQL
                                     | Managed Identity -> PostgreSQL Entra
                                     +-> private release and backup Blob accounts
```

The gateway follows the capstone core with a public HTTP listener; HTTPS/redirect is an optional bonus and is not configured because there is no domain/certificate. Authentication is absent, so use synthetic data only. The deploy script requires explicit `ALLOW_PUBLIC_HTTP_DEMO=true` before it can expose the demo. See [Terraform setup and security notes](terraform/README.md), [architecture diagram](terraform/docs/architecture.md), and [capstone answers](terraform/ANSWERS.md).

For an end-to-end deploy from Bash (Linux, WSL, or Git Bash), prepare `terraform/dev.tfvars`, sign in using `az login`, bootstrap remote state once, then deploy:

```bash
bash ./scripts/bootstrap-terraform-state.sh
ALLOW_PUBLIC_HTTP_DEMO=true bash ./deploy-azure.sh dev
```

The deployment script validates/plans first and requires you to type `YES` before it applies infrastructure. It then uses the signed-in Entra identity to bootstrap PostgreSQL, creates private blob containers, uploads the app release, and checks the public gateway health endpoint. Use `bash ./scripts/run-vmss-command.sh dev` to run a diagnostic command through the Azure control plane without opening SSH. Before teardown, use `bash ./scripts/backup-postgres-before-destroy.sh dev` to create a private database export.

## Live Azure Deployment Evidence (`m1` – `m6`)

- **Demo Video**: [terraform-capstone-video.mp4](docs/screenshots/terraform-capstone-video.mp4)
- **Milestone 01 — Project Foundation & Remote State (`init` & `validate`)**:
  ![m1-init-validate](docs/screenshots/m1-init-validate.png)
- **Milestone 02 — VNet & Multi-Tier Subnet Plan**:
  ![m2-vnet-plan](docs/screenshots/m2-vnet-plan.png)
- **Milestone 03 — Least-Privilege Security Groups (NSG & ASG)**:
  ![m3-security-groups-1](docs/screenshots/m3-security-groups-1.png)
  ![m3-security-groups-2](docs/screenshots/m3-security-groups-2.png)
- **Milestone 04 — Application Gateway & Auto-Scaling VMSS**:
  ![m6-web-app-live](docs/screenshots/m6-web-app-live.png)
  ![m4-vmss-scaling-1](docs/screenshots/m4-vmss-scaling-1.png)
  ![m4-vmss-scaling-2](docs/screenshots/m4-vmss-scaling-2.png)
- **Milestone 05 — Private PostgreSQL (Entra Auth) & Storage HTTPS Enforcement**:
  ![m5-db-and-storage-https](docs/screenshots/m5-db-and-storage-https.png)
- **Milestone 06 — Production (`prod.tfvars`) Plan & Teardown (`terraform destroy`)**:
  ![m6-prod-plan](docs/screenshots/m6-prod-plan.png)
  - Optional Teardown Screenshot: `docs/screenshots/m6-terraform-destroy.png`


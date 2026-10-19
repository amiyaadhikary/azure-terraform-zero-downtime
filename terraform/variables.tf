variable "subscription_id" {
  type        = string
  description = "Azure subscription ID. Supply via TF_VAR_subscription_id or local tfvars."
}
variable "owner" {
  type        = string
  description = "Owner/team tag applied to Azure resources."
  default     = "platform-team"
}
variable "location" {
  type    = string
  default = "centralindia"
}
variable "project_name" {
  type    = string
  default = "student-registration"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Use 3-20 lowercase letters, digits, or hyphens."
  }
}
variable "environment" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}
variable "vnet_cidr" {
  type    = string
  default = "10.20.0.0/16"
}
variable "availability_zones" {
  type        = list(string)
  description = "Azure availability zones used by the VMSS and zone-capable ingress services. Set to zones supported by the selected region and VM SKU."
  default     = ["1", "2"]
  validation {
    condition     = length(var.availability_zones) >= 2 && length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "availability_zones must contain at least two distinct zone numbers."
  }
}
variable "enable_bastion" {
  type        = bool
  description = "Create optional Azure Bastion for VM access; costs extra and is off by default."
  default     = false
}
variable "bastion_sku_name" {
  type        = string
  description = "Azure Bastion SKU used only when enable_bastion is true."
  default     = "Basic"
}
variable "database_admin_principal_name" {
  type        = string
  description = "Microsoft Entra UPN or service-principal display name used as the PostgreSQL Entra administrator."
}
variable "database_admin_principal_type" {
  type        = string
  description = "Microsoft Entra administrator type for the current Terraform identity."
  default     = "User"
  validation {
    condition     = contains(["User", "ServicePrincipal", "Group"], var.database_admin_principal_type)
    error_message = "database_admin_principal_type must be User, ServicePrincipal, or Group."
  }
}
variable "database_app_login" {
  type        = string
  description = "Least-privilege PostgreSQL role used by the API; create it with the database bootstrap script."
  default     = "student_app"
  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", var.database_app_login))
    error_message = "database_app_login must be a valid PostgreSQL role name, up to 63 characters."
  }
}
variable "database_name" {
  type    = string
  default = "student_registration"
}
variable "postgres_version" {
  type    = string
  default = "16"
}
variable "postgres_sku_name" {
  type    = string
  default = "B_Standard_B1ms"
}
variable "database_storage_mb" {
  type    = number
  default = 32768
}
variable "database_backup_retention_days" {
  type    = number
  default = 7
}
variable "database_zone" {
  type    = string
  default = "1"
}
variable "database_high_availability" {
  type    = bool
  default = false
}
variable "database_deletion_protection" {
  type        = bool
  description = "Create a CanNotDelete Azure management lock on the PostgreSQL server."
  default     = false
}
variable "vmss_sku" {
  type        = string
  description = "Linux VM size used by the API scale set."
  default     = "Standard_B2ts_v2"
}
variable "api_instance_count" {
  type        = number
  description = "Initial/desired API VMSS instance count."
  default     = 1
}
variable "api_min_instances" {
  type        = number
  description = "Minimum API VMSS instance count."
  default     = 1
}
variable "api_max_instances" {
  type        = number
  description = "Maximum API VMSS instance count."
  default     = 2
}
variable "vm_admin_ssh_public_key" {
  type        = string
  description = "SSH public key required by Azure Linux VMSS. No SSH inbound rule is created; use Bastion or a controlled Azure management path."
  sensitive   = true
}
variable "vm_admin_username" {
  type        = string
  description = "Non-root Linux administrator account used only with a separately controlled SSH private key."
  default     = "azureuser"
}
variable "api_release_version" {
  type        = string
  description = "Immutable release ID included in VMSS custom data and the release archive filename."
  default     = "initial"
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$", var.api_release_version))
    error_message = "api_release_version must be 1-40 characters, start with a letter or digit, and contain only letters, digits, hyphens, or underscores."
  }
}
variable "storage_replication_type" {
  type        = string
  description = "Azure Storage replication SKU. Prefer ZRS for production when the region supports it."
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "storage_replication_type must be a supported Azure Storage replication SKU."
  }
}

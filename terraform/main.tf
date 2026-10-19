locals {
  resource_suffix = substr(sha256("${var.subscription_id}/${var.project_name}/${var.environment}"), 0, 6)
  name_prefix     = "${var.project_name}-${var.environment}-${local.resource_suffix}"
  # Preserve the existing ranges while deriving them from the VNet CIDR.
  # Azure subnets are regional; zonal VMSS instances share the app subnet.
  app_subnet_cidr                 = cidrsubnet(var.vnet_cidr, 8, 1)
  database_subnet_cidr            = cidrsubnet(var.vnet_cidr, 8, 2)
  application_gateway_subnet_cidr = cidrsubnet(var.vnet_cidr, 8, 4)
  bastion_subnet_cidr             = cidrsubnet(var.vnet_cidr, 10, 48)
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "Terraform"
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

module "vnet" {
  source                          = "./modules/vnet"
  name_prefix                     = local.name_prefix
  location                        = var.location
  resource_group_name             = azurerm_resource_group.main.name
  vnet_cidr                       = var.vnet_cidr
  app_subnet_cidr                 = local.app_subnet_cidr
  application_gateway_subnet_cidr = local.application_gateway_subnet_cidr
  database_subnet_cidr            = local.database_subnet_cidr
  bastion_subnet_cidr             = local.bastion_subnet_cidr
  enable_bastion                  = var.enable_bastion
  tags                            = local.common_tags
}

module "app_security_group" {
  source              = "./modules/security_groups"
  name                = "nsg-${local.name_prefix}-app"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.app_subnet_id
  security_rules = concat([
    {
      name                       = "Allow-App-From-Application-Gateway"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = local.application_gateway_subnet_cidr
      destination_address_prefix = local.app_subnet_cidr
      destination_port_range     = "5000"
    }
    ], var.enable_bastion ? [
    {
      name                       = "Allow-SSH-From-Bastion"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = local.bastion_subnet_cidr
      destination_address_prefix = local.app_subnet_cidr
      destination_port_range     = "22"
    }
  ] : [])
  tags = local.common_tags
}

resource "azurerm_application_security_group" "api" {
  name                = "asg-${local.name_prefix}-api"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

module "database_security_group" {
  source              = "./modules/security_groups"
  name                = "nsg-${local.name_prefix}-db"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.database_subnet_id
  security_rules = [
    {
      name                                  = "Allow-App-PostgreSQL"
      priority                              = 100
      direction                             = "Inbound"
      access                                = "Allow"
      protocol                              = "Tcp"
      source_application_security_group_ids = [azurerm_application_security_group.api.id]
      destination_address_prefix            = local.database_subnet_cidr
      destination_port_range                = "5432"
    },
    {
      name                       = "Deny-Other-VNet-PostgreSQL"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "Tcp"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = local.database_subnet_cidr
      destination_port_range     = "5432"
    }
  ]
  tags = local.common_tags
}

module "postgresql" {
  source                       = "./modules/postgresql"
  name_prefix                  = local.name_prefix
  location                     = var.location
  resource_group_name          = azurerm_resource_group.main.name
  delegated_subnet_id          = module.vnet.database_subnet_id
  private_dns_zone_id          = module.vnet.private_dns_zone_id
  tenant_id                    = data.azurerm_client_config.current.tenant_id
  administrator_principal_name = var.database_admin_principal_name
  administrator_principal_id   = data.azurerm_client_config.current.object_id
  administrator_principal_type = var.database_admin_principal_type
  database_name                = var.database_name
  postgres_version             = var.postgres_version
  sku_name                     = var.postgres_sku_name
  storage_mb                   = var.database_storage_mb
  backup_retention_days        = var.database_backup_retention_days
  zone                         = var.database_zone
  high_availability_enabled    = var.database_high_availability
  tags                         = local.common_tags
  depends_on                   = [module.vnet, module.database_security_group]
}

resource "azurerm_management_lock" "postgresql_delete_protection" {
  count      = var.database_deletion_protection ? 1 : 0
  name       = "lock-${local.name_prefix}-postgresql-delete"
  scope      = module.postgresql.server_id
  lock_level = "CanNotDelete"
  notes      = "Remove this Terraform-managed lock deliberately before deleting the PostgreSQL server."
}

module "storage" {
  source                   = "./modules/storage"
  name_prefix              = local.name_prefix
  location                 = var.location
  resource_group_name      = azurerm_resource_group.main.name
  unique_suffix            = local.resource_suffix
  account_replication_type = var.storage_replication_type
  tags                     = local.common_tags
}

resource "azurerm_storage_account" "database_backups" {
  name                            = "stb${substr(replace(local.name_prefix, "-", ""), 0, 20)}"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = var.storage_replication_type
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true
  public_network_access_enabled   = true
  blob_properties {
    versioning_enabled = true
  }
  tags = local.common_tags
}

module "application_gateway" {
  source              = "./modules/application_gateway"
  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.application_gateway_subnet_id
  availability_zones  = var.availability_zones
  tags                = local.common_tags
}

resource "azurerm_public_ip" "nat" {
  name                = "pip-${local.name_prefix}-nat"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "StandardV2"
  sku_tier            = "Regional"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway" "app" {
  name                = "nat-${local.name_prefix}-app"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  # StandardV2 is zone-redundant in Azure; one gateway can serve the zonal app subnet.
  sku_name                = "StandardV2"
  idle_timeout_in_minutes = 10
  tags                    = local.common_tags
}

resource "azurerm_nat_gateway_public_ip_association" "app" {
  nat_gateway_id       = azurerm_nat_gateway.app.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "app" {
  subnet_id      = module.vnet.app_subnet_id
  nat_gateway_id = azurerm_nat_gateway.app.id
}

module "vmss" {
  source                              = "./modules/vmss"
  name_prefix                         = local.name_prefix
  location                            = var.location
  resource_group_name                 = azurerm_resource_group.main.name
  subnet_id                           = module.vnet.app_subnet_id
  application_security_group_id       = azurerm_application_security_group.api.id
  application_gateway_backend_pool_id = module.application_gateway.api_backend_pool_id
  vm_sku                              = var.vmss_sku
  initial_instances                   = var.api_instance_count
  availability_zones                  = var.availability_zones
  admin_username                      = var.vm_admin_username
  admin_ssh_public_key                = var.vm_admin_ssh_public_key
  blob_endpoint                       = module.storage.blob_endpoint
  release_container_name              = module.storage.release_container_name
  release_blob_name                   = "api-${var.api_release_version}.zip"
  release_version                     = var.api_release_version
  database_host                       = module.postgresql.fqdn
  database_name                       = module.postgresql.database_name
  database_user                       = var.database_app_login
  tags                                = local.common_tags
  depends_on = [
    module.app_security_group,
    azurerm_nat_gateway_public_ip_association.app,
    azurerm_subnet_nat_gateway_association.app
  ]
}

resource "azurerm_role_assignment" "vmss_reads_release_artifacts" {
  # This storage account contains private release artifacts only; account scope
  # avoids a data-plane/RBAC creation cycle for the bootstrap container.
  scope                            = module.storage.storage_account_id
  role_definition_name             = "Storage Blob Data Reader"
  principal_id                     = module.vmss.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "vmss_writes_database_backups" {
  # The dedicated account contains only encrypted, non-public database dumps.
  scope                            = azurerm_storage_account.database_backups.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = module.vmss.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# The identity executing this stack must be able to upload versioned releases.
resource "azurerm_role_assignment" "operator_uploads_application" {
  scope                = module.storage.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "operator_manages_database_backups" {
  scope                = azurerm_storage_account.database_backups.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

module "bastion" {
  count               = var.enable_bastion ? 1 : 0
  source              = "./modules/bastion"
  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.bastion_subnet_id
  sku_name            = var.bastion_sku_name
  tags                = local.common_tags
}

resource "azurerm_monitor_autoscale_setting" "api" {
  name                = "autoscale-${local.name_prefix}-api"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  target_resource_id  = module.vmss.id
  profile {
    name = "cpu-autoscale"
    capacity {
      default = var.api_instance_count
      minimum = var.api_min_instances
      maximum = var.api_max_instances
    }
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = module.vmss.id
        metric_namespace   = "Microsoft.Compute/virtualMachineScaleSets"
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = module.vmss.id
        metric_namespace   = "Microsoft.Compute/virtualMachineScaleSets"
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
  tags = local.common_tags
}

resource "azurerm_application_insights" "main" {
  name                = "appi-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  tags                = local.common_tags
}

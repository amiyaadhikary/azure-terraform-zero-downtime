resource "azurerm_postgresql_flexible_server" "main" {
  name                          = "psql-${var.name_prefix}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = var.postgres_version
  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  zone                          = var.zone
  sku_name                      = var.sku_name
  storage_mb                    = var.storage_mb
  backup_retention_days         = var.backup_retention_days
  public_network_access_enabled = false
  geo_redundant_backup_enabled  = false
  tags                          = var.tags

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = var.tenant_id
  }

  dynamic "high_availability" {
    for_each = var.high_availability_enabled ? [1] : []
    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = var.zone == "1" ? "2" : "1"
    }
  }

}

resource "azurerm_postgresql_flexible_server_active_directory_administrator" "main" {
  server_name         = azurerm_postgresql_flexible_server.main.name
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  object_id           = var.administrator_principal_id
  principal_name      = var.administrator_principal_name
  principal_type      = var.administrator_principal_type
}

resource "azurerm_postgresql_flexible_server_database" "main" {
  name       = var.database_name
  server_id  = azurerm_postgresql_flexible_server.main.id
  collation  = "en_US.utf8"
  charset    = "UTF8"
  depends_on = [azurerm_postgresql_flexible_server_active_directory_administrator.main]
}

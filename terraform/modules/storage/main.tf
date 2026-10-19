resource "azurerm_storage_account" "main" {
  name                            = "st${substr(replace(var.name_prefix, "-", ""), 0, 12)}${var.unique_suffix}"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = var.account_replication_type
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true
  public_network_access_enabled   = true
  tags                            = var.tags
  blob_properties {
    versioning_enabled = true
  }
}


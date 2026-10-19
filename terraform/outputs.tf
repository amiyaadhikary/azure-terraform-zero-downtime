output "resource_group_name" { value = azurerm_resource_group.main.name }
output "vnet_id" { value = module.vnet.virtual_network_id }
output "subnet_ids" { value = module.vnet.subnet_ids }
output "api_url" { value = module.application_gateway.url }
output "api_app_name" { value = module.vmss.name }
output "frontend_url" { value = module.application_gateway.url }
output "application_gateway_public_ip" { value = module.application_gateway.public_ip }
output "vmss_name" { value = module.vmss.name }
output "vmss_id" { value = module.vmss.id }
output "storage_account_name" { value = module.storage.storage_account_name }
output "database_backup_storage_account_name" { value = azurerm_storage_account.database_backups.name }
output "release_container_name" { value = module.storage.release_container_name }
output "postgres_fqdn" { value = module.postgresql.fqdn }
output "postgres_database_name" { value = module.postgresql.database_name }
output "bastion_public_ip" {
  description = "Public IP of Azure Bastion; null when enable_bastion is false."
  value       = try(module.bastion[0].bastion_public_ip, null)
}
output "database_app_login" { value = var.database_app_login }
output "vmss_principal_id" { value = module.vmss.principal_id }
output "database_admin_principal_name" { value = var.database_admin_principal_name }

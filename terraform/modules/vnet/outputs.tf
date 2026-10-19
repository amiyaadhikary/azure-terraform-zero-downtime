output "virtual_network_id" { value = azurerm_virtual_network.main.id }
output "app_subnet_id" { value = azurerm_subnet.app.id }
output "application_gateway_subnet_id" { value = azurerm_subnet.application_gateway.id }
output "database_subnet_id" { value = azurerm_subnet.database.id }
output "bastion_subnet_id" { value = try(azurerm_subnet.bastion[0].id, null) }
output "subnet_ids" {
  description = "Subnet IDs for the VNet tiers in stable app, application-gateway, database order. Bastion is omitted when disabled."
  value       = concat([azurerm_subnet.app.id, azurerm_subnet.application_gateway.id, azurerm_subnet.database.id], try([azurerm_subnet.bastion[0].id], []))
}
output "private_dns_zone_id" { value = azurerm_private_dns_zone.postgres.id }

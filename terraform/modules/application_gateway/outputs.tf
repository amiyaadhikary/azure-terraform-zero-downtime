output "url" {
  description = "HTTP demo URL served by the public Application Gateway."
  value       = "http://${azurerm_public_ip.main.fqdn}"
}
output "public_ip" { value = azurerm_public_ip.main.ip_address }
output "api_backend_pool_id" {
  value = one([for pool in azurerm_application_gateway.main.backend_address_pool : pool.id if pool.name == "api-vmss-pool"])
}

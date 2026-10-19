output "id" { value = azurerm_linux_virtual_machine_scale_set.api.id }
output "name" { value = azurerm_linux_virtual_machine_scale_set.api.name }
output "principal_id" { value = azurerm_linux_virtual_machine_scale_set.api.identity[0].principal_id }

resource "azurerm_linux_virtual_machine_scale_set" "api" {
  name                            = "vmss-${var.name_prefix}-api"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  sku                             = var.vm_sku
  instances                       = var.initial_instances
  zones                           = var.availability_zones
  zone_balance                    = true
  admin_username                  = var.admin_username
  disable_password_authentication = true
  upgrade_mode                    = "Rolling"
  rolling_upgrade_policy {
    max_batch_instance_percent              = 33
    max_unhealthy_instance_percent          = 50
    max_unhealthy_upgraded_instance_percent = 100
    pause_time_between_batches              = "PT1M"
  }
  custom_data = base64encode(templatefile("${path.module}/cloud-init.sh.tftpl", {
    blob_endpoint     = trimsuffix(var.blob_endpoint, "/")
    release_container = var.release_container_name
    release_blob_name = var.release_blob_name
    release_version   = var.release_version
    database_host     = var.database_host
    database_name     = var.database_name
    database_user     = var.database_user
  }))
  tags = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  identity {
    type = "SystemAssigned"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface {
    name    = "api-nic"
    primary = true

    ip_configuration {
      name                                         = "internal"
      primary                                      = true
      subnet_id                                    = var.subnet_id
      application_security_group_ids               = [var.application_security_group_id]
      application_gateway_backend_address_pool_ids = [var.application_gateway_backend_pool_id]
    }
  }

  extension {
    name                       = "application-health"
    publisher                  = "Microsoft.ManagedServices"
    type                       = "ApplicationHealthLinux"
    type_handler_version       = "1.0"
    auto_upgrade_minor_version = true
    settings = jsonencode({
      protocol    = "http"
      port        = 5000
      requestPath = "/health"
    })
  }
}

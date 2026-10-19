variable "name_prefix" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "subnet_id" { type = string }
variable "application_security_group_id" { type = string }
variable "application_gateway_backend_pool_id" { type = string }
variable "vm_sku" { type = string }
variable "initial_instances" { type = number }
variable "availability_zones" {
  type        = list(string)
  description = "Availability zones across which to spread VMSS instances."
}
variable "admin_username" { type = string }
variable "admin_ssh_public_key" {
  type      = string
  sensitive = true
}
variable "blob_endpoint" { type = string }
variable "release_container_name" { type = string }
variable "release_blob_name" { type = string }
variable "release_version" { type = string }
variable "database_host" { type = string }
variable "database_name" { type = string }
variable "database_user" { type = string }
variable "tags" { type = map(string) }

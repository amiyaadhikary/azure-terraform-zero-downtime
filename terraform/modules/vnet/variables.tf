variable "name_prefix" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "vnet_cidr" { type = string }
variable "app_subnet_cidr" { type = string }
variable "application_gateway_subnet_cidr" { type = string }
variable "database_subnet_cidr" { type = string }
variable "bastion_subnet_cidr" { type = string }
variable "enable_bastion" {
  type        = bool
  description = "Create the dedicated AzureBastionSubnet when the optional Bastion module is enabled."
  default     = false
}
variable "tags" { type = map(string) }

variable "name_prefix" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "subnet_id" { type = string }
variable "sku_name" {
  type        = string
  description = "Azure Bastion SKU. Basic is the lower-cost entry point; verify regional availability."
  default     = "Basic"
}
variable "tags" { type = map(string) }

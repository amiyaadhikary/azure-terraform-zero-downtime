variable "name_prefix" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "unique_suffix" { type = string }
variable "account_replication_type" {
  type        = string
  description = "Azure Storage replication SKU (LRS for dev; ZRS for zone-resilient production when supported)."
}
variable "tags" { type = map(string) }

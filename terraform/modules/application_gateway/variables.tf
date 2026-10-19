variable "name_prefix" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "subnet_id" { type = string }
variable "availability_zones" {
  type        = list(string)
  description = "Availability zones supported by the selected region for Application Gateway v2."
}
variable "tags" { type = map(string) }

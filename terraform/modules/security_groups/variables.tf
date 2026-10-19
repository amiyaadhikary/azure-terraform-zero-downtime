variable "name" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "subnet_id" { type = string }
variable "tags" { type = map(string) }
variable "security_rules" {
  type = list(object({
    name                                  = string
    priority                              = number
    direction                             = string
    access                                = string
    protocol                              = string
    source_address_prefix                 = optional(string)
    source_application_security_group_ids = optional(list(string))
    destination_address_prefix            = string
    destination_port_range                = string
  }))
  default = []
}

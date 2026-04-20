variable "rg_name"        { type = string }
variable "location"                    { type = string }
variable "prefix"                      { type = string }
variable "tags"                        { type = map(string) }
variable "hub_vnet_id"   { type = string }
variable "inbound_subnet_id"   { type = string }
variable "outbound_subnet_id"  { type = string }

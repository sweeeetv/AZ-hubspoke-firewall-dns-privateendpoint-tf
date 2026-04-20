variable "rg_name" {type = string}
variable "location" {type = string}
variable "tags" {type = map(string)}
variable "prefix" {type = string}
variable "hub_address_space"   { type = string }
variable "spoke1_address_space" { type = string }
variable "spoke2_address_space" { type = string }
variable "mac_pub_ip" {type = string}
variable "admin_username" {type = string}
variable "dns_servers" {
    description = "DNS servers for the hub vnet. in Step 1: [] -> azure default dns resolver. in Step 2: [private ip of dnsr-in] -> private dns resolver."
    type = list(string)
    default = []
}


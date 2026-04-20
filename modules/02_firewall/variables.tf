variable "rg_name"        { type = string }
variable "location"                    { type = string }
variable "prefix"                      { type = string }
variable "tags"                        { type = map(string) }
variable "hub_vnet_name"               { type = string }
variable "spoke1_workload_subnet_id"   { type = string }
variable "spoke2_pe_subnet_id"         { type = string }
variable "log_analytics_workspace_id"  { type = string }


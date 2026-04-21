# step 0 - root files, shared resources, variables, outputs
# step 1 - hub, spoke, subnets, peering, VM
# step 2 - deploy_firewall - firewall, UDRs, route tables 
# step 3 - deploy_dns_resolver - dns private resolver, private dns zones.
#─────────────────────────────────────────────────────────────────────────────
# shared resources
#─────────────────────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.prefix}"
  location = var.location
    tags     = var.tags
} 

#firewall diags + flow logs
resource "azurerm_log_analytics_workspace" "main" {
    name ="law-${var.prefix}"
    resource_group_name = azurerm_resource_group.main.name
    location = var.location
    sku = "PerGB2018" 
    retention_in_days ="30"
    tags =var.tags
}


# ─────────────────────────────────────────────────────────────────────────────
# step 1 - hub, spokes, peering - always on
# ─────────────────────────────────────────────────────────────────────────────
module "hub" {
    source = "./modules/01_hub"
    rg_name = azurerm_resource_group.main.name
    location = var.location
    tags = var.tags
    prefix = var.prefix
    hub_address_space = var.hub_address_space
    spoke1_address_space = var.spoke1_address_space
    spoke2_address_space = var.spoke2_address_space
    //if true, then pass the private ip of dnsr-in to hub vnet dns servers. If false, pass empty list -> azure default dns.
    //dns_servers = var.deploy_dns_resolver ? [module.dns_resolver[0].inbound_endpoint_ip] : []
    dns_servers = var.dns_servers
    mac_pub_ip = var.mac_pub_ip
    admin_username = var.admin_username
}
# # ─────────────────────────────────────────────────────────────────────────────
# # Step 2 - firewall + UDRs
# # ─────────────────────────────────────────────────────────────────────────────
module "firewall" {
    count = var.deploy_firewall ? 1 : 0
    source = "./modules/02_firewall"

    rg_name = azurerm_resource_group.main.name
    location = var.location
    tags = var.tags
    prefix = var.prefix
    hub_vnet_name = module.hub.hub_vnet_name
    spoke1_workload_subnet_id = module.hub.spoke1_workload_subnet_id
    spoke2_pe_subnet_id = module.hub.spoke2_pe_subnet_id
    fw_subnet_id = module.hub.hub_fw_subnet_id 
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}
# ─────────────────────────────────────────────────────────────────────────────
# Step 3 - DNS Private Resolver + Private DNS zones
# ─────────────────────────────────────────────────────────────────────────────
module "dns_resolver" {
  #有或没有 dns resolver 都要部署 hub vnet。  
  #if count exists, then it is a list of dns resolvers.
  count  = var.deploy_dns_resolver ? 1 : 0
  source = "./modules/03_dns_resolver"
  rg_name = azurerm_resource_group.main.name
  location            = var.location
  prefix              = var.prefix
  tags                = var.tags
  hub_vnet_id         = module.hub.hub_vnet_id
  inbound_subnet_id   = module.hub.hub_dnsr_inbound_subnet_id
  outbound_subnet_id  = module.hub.hub_dnsr_outbound_subnet_id
} 
# # ─────────────────────────────────────────────────────────────────────────────
# # step 4 - key vault + private end 
# # ─────────────────────────────────────────────────────────────────────────────
# module "key_vault" {
#   count = var.deploy_key_vault ? 1 : 0
#   source = "./modules/04_key_vault"  
#   rg_name = azurerm_resource_group.main.name
#   location            = var.location
#   prefix              = var.prefix
#   tags                = var.tags
#   //private ep's nic lives in the subnet of spoke2.
#   spoke2_pe_subnet_id        = module.hub.spoke2_pe_subnet_id
#   //tell azure where to find the dns resolver. If not deployed, then pass empty string -> azure default dns.
#   private_dns_zone_id = var.deploy_dns_resolver ? module.dns_resolver[0].kv_private_dns_zone_id : ''
#   //needed for rbac to let the vm access kv secrets.
#   vm_principal_id = module.hub.vm_principal_id
#   firewall_policy_id = var.deploy_firewall ? module.firewall[0].firewall_policy_id : null
# }
# # ─────────────────────────────────────────────────────────────────────────────
# # step 5 - storage account, azure files, private endpoint
# # ─────────────────────────────────────────────────────────────────────────────
# module "storage" {
#   count  = var.deploy_storage ? 1 : 0
#   source = "./modules/05_storage"

#   rg_name = azurerm_resource_group.main.name
#   location            = var.location
#   prefix              = var.prefix
#   tags                = var.tags
#   spoke2_pe_subnet_id = module.hub.spoke2_pe_subnet_id
#   private_dns_zone_id = var.deploy_dns_resolver ? module.dns_resolver[0].storage_private_dns_zone_id : "" 
#   firewall_policy_id  = var.deploy_firewall ? module.firewall[0].firewall_policy_id : ""
# }
# # ─────────────────────────────────────────────────────────────────────────────
# # step 6 - service bus + pe
# # ─────────────────────────────────────────────────────────────────────────────
# module "service_bus" {
#   count  = var.deploy_service_bus ? 1 : 0
#   source = "./modules/06_service_bus"

#   rg_name = azurerm_resource_group.main.name
#   location            = var.location
#   prefix              = var.prefix
#   tags                = var.tags
#   spoke2_pe_subnet_id = module.hub.spoke2_pe_subnet_id
#   private_dns_zone_id = var.deploy_dns_resolver ? module.dns_resolver[0].service_bus_private_dns_zone_id : "" 
#   firewall_policy_id  = var.deploy_firewall ? module.firewall[0].firewall_policy_id : ""
# }
# # ─────────────────────────────────────────────────────────────────────────────
# # step 7 - nsg flow logs + traffic analytics
# # ─────────────────────────────────────────────────────────────────────────────
# module "monitoring" {
#   count  = var.deploy_monitoring ? 1 : 0
#   source = "./modules/07_monitoring"

#   resource_group_name        = azurerm_resource_group.main.name
#   location                   = var.location
#   prefix                     = var.prefix
#   tags                       = var.tags
#   log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
#   hub_nsg_id                 = module.hub.hub_nsg_id
#   spoke1_nsg_id              = module.hub.spoke1_nsg_id         
#   spoke2_nsg_id              = module.hub.spoke2_nsg_id
# }
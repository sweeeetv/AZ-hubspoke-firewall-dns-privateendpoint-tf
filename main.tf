# step 0 - root files, shared resources, variables, outputs
# step 1 - hub, spoke, peering
# ─────────────────────────────────────────────────────────────────────────────
# shared resources
# ─────────────────────────────────────────────────────────────────────────────
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
    retention_in_days ="10"
    tags =var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# step 1 - hub, spoke, peering - always on
# ─────────────────────────────────────────────────────────────────────────────
module "hub" {
    source = "./modules/01-hub"
    rg_name = azurerm_resource_group.main.name
    location = var.location
    tags = var.tags
    prefix = var.prefix
    hub_address_space = var.hub_address_space
    spoke1_address_space = var.spoke1_address_space
    spoke2_address_space = var.spoke2_address_space
    //if true, then pass the private ip of dnsr-in to hub vnet dns servers. If false, pass empty list -> azure default dns.
    dns_servers = var.deploy_dns_resolver ? [module.dns_resolver[0].inbound_endpoint_ip] : []
    mac_pub_ip = var.mac_pub_ip
    admin_username = var.admin_username
}
# ─────────────────────────────────────────────────────────────────────────────
# Step 3 - DNS Private Resolver + Private DNS zones
# ─────────────────────────────────────────────────────────────────────────────
module "dns_resolver" {
  #有或没有 dns resolver 都要部署 hub vnet。
  #if count exists, then it is a list of dns resolvers.
  count  = var.deploy_dns_resolver ? 1 : 0
  source = "./modules/03_dns_resolver"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  prefix              = var.prefix
  tags                = var.tags
  hub_vnet_id         = module.hub.hub_vnet_id
  inbound_subnet_id   = module.hub.hub_dnsr_inbound_subnet_id
  outbound_subnet_id  = module.hub.hub_dnsr_outbound_subnet_id
}


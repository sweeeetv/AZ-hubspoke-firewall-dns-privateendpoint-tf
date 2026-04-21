# (The system route Azure injects (10.2.0.0/16 → VNetPeering) points directly at spoke 2 over # the backbone — it doesn't route through the hub VNet's address space at all.)
# step 2 firewall : standard Firewall, fw policy, UDRs on spoke subnets.
# diagnostic settings -> LAW
# SESSION GOAL (step 2):
#   Set deploy_firewall = true, apply, then verify:
#   1. `terraform output firewall_private_ip` matches effective route next hop
#   2. SSH still works (SSH goes through NSG, not firewall — this is fine)
#   3. From VM: curl ifconfig.me returns the FIREWALL public IP, not VM pip
#   4. AZFWApplicationRule logs in Log Analytics show the curl request
# KEY: Two routes are needed on each spoke route table:
#   - 0.0.0.0/0  → firewall  (internet-bound)
#   - 10.0.0.0/8 → firewall  (east-west / spoke-to-spoke)
# ───────────────────────────────────────────────────

resource "azurerm_public_ip" "firewall" {
  name                = "pip-${var.prefix}-appfw"
  resource_group_name = var.rg_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard" 
  tags                = var.tags
}
//policy can be attached to multiple fws, make the management easier. 
resource "azurerm_firewall_policy" "main"{
    name                = "fwpolicy-${var.prefix}"
    resource_group_name = var.rg_name
    location            = var.location
    sku                 = "Standard" //must much fw's sku.
    tags                = var.tags
    # Actively block known malicious IPs/domains
    # threat_intelligence_mode = "Deny"
    dns {
        proxy_enabled = true//this enables DNS proxy, so firewall can intercept and process DNS queries.
        # Forward unknown queries to your Hub Resolver (Once built)
        # servers = [var.hub_dns_resolver_ip]
    }
}
//fw sku:
//standard - FQDN filtering, threat intelligence, web categories
//premium - IDPS, TLS inspection, URL filtering, signature-based detection
resource "azurerm_firewall" "hub" {
    name                = "fw-${var.prefix}-hub"
    resource_group_name = var.rg_name
    location            = var.location
    sku_tier                = "Standard"
    sku_name                = "AZFW_VNet"//name: deployment model - where the fw lives. either AZFW_VNet or AZFW_Hub. 
    tags                = var.tags
    firewall_policy_id   = azurerm_firewall_policy.main.id
    ip_configuration {
        public_ip_address_id = azurerm_public_ip.firewall.id
        subnet_id            = var.fw_subnet_id //AzureFirewallSubnet
        name ="fw-ipconfig"
    }
    # lifecycle {
    # ignore_changes = [ip_configuration[0].subnet_id]
    # # Remove ignore_changes once subnet_id is properly wired
    # }
}

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                           = "diag-fw-${var.prefix}"
  target_resource_id             = azurerm_firewall.hub.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  enabled_log {
    category_group = "allLogs"
  } //captures: AZFWApplicationRule, AZFWNetworkRule, AZFWThreatIntel, AZFWDnsProxy
  metric {
    category = "AllMetrics"
  } 
}
//define the rules for fw in this collection_group
resource "azurerm_firewall_policy_rule_collection_group" "baseline" {
    name                    = "rcg-baseline-${var.prefix}"
    firewall_policy_id      = azurerm_firewall_policy.main.id
    priority                = 200
    // network rules - fw inspects by ip + port only (not FQDN), Standard SKU cannot inspect domain names for SMB traffic.
    network_rule_collection {
      name = "rule-collection-sp1-to-sp2"
      priority = 100
      action = "Allow"
      rule {
        name = "allow-smb-to-storage-pe" //allows file sharing->VM in s1 to rw files to a storage acc ep in sp2
        protocols = ["TCP"]
        source_addresses = ["10.1.1.0/24"]
        destination_addresses = ["10.2.1.0/24"]
        destination_ports = ["445"]
      }
      rule {
        name = "allow-icmp-for-testing"
        protocols = ["ICMP"]
        source_addresses = ["10.1.0.0/16", "10.2.0.0/16"]
        destination_addresses = ["10.1.0.0/16", "10.2.0.0/16"]
        destination_ports = ["*"]
      }
    }
    //for https traffic - fw resolves FQDNs at inspection time, requires dns proxy_enabled.
    application_rule_collection {
      name = "rule-collection-app-paas-access"
      priority = 200
      action = "Allow"
      rule {
        name = "allow-kv"
        source_addresses =["10.1.1.0/24"]
        destination_fqdns = [
          "*.vaultcore.azure.net",
          "login.microsoftonline.com", //VM must first prove its identity
          "*.identity.azure.net"
        ]
        protocols {
          type = "Https"
          port = 443
        }
      } 
      rule {
        name = "allow-storage"
        source_addresses =["10.1.1.0/24"]
        destination_fqdns = [
          "*.blob.core.windows.net",
          "*.file.core.windows.net"
        ]
        protocols {
          type = "Https"
          port = 443
        }
      }
      rule {
        name = "allow-servicebus"
        source_addresses =["10.1.1.0/24"]
        destination_fqdns = [
          "*.servicebus.windows.net"
        ]
        protocols {
          type = "Https"
          port = 443
        }
      }
      //fw's default behavior is implicit deny. So this explicit outbound rule is needed for internet bound traffic for the vm.
      //step 4 needs to install azure cli on the vm; 
      //step 6 needs install packets for service bus and azure-identity via pip.
      rule {
        name = "allow-vm-outbound"
        source_addresses =["10.1.1.0/24"]
        destination_fqdns = [
          "packages.microsoft.com", # Azure CLI / VM Agents
          "aka.ms", //install script redirect
          "*.ubuntu.com",
          "*.canonical.com",
          "ifconfig.me",
          "*.pypi.org",    # Python Pip core, pip, step 6
          "*.pythonhosted.org", # Python Pip dependencies
        ]
        protocols {
          type = "Https" 
          port = 443
        }
        protocols {
          type = "Http"
          port = 80
        }
      }
    }   
}


# ──────────────────────────────────────────────────────────────────────────────────
# ───────────────────────────────── UDR ────────────────────────────────────────────
# ──  Route table: Spoke 1 ─────────────────────────────────────────────────────────
resource "azurerm_route_table" "sp1" {
  name                = "rt-${var.prefix}-sp1"
  resource_group_name = var.rg_name
  location            = var.location
  tags                = var.tags
  bgp_route_propagation_enabled = false //prevent onprem bgp routes from being injected into spoke routes. so the udr won't get overriden.
}
//seperate routes are better, so you can add modify and delete them individually.
resource "azurerm_route" "sp1_default"{
  name = "route-default-to-fw"
  resource_group_name = var.rg_name
  route_table_name = azurerm_route_table.sp1.name
  address_prefix = "0.0.0.0/0" //internet-bound
  next_hop_type = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}
resource "azurerm_route" "sp1_rfc1918"{
  name = "route-rfc1918-to-fw"
  resource_group_name = var.rg_name
  route_table_name = azurerm_route_table.sp1.name
  address_prefix = "10.0.0.0/8"
  next_hop_type = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}
resource "azurerm_subnet_route_table_association" "sp1_rt_association" {
  subnet_id      = var.spoke1_workload_subnet_id
  route_table_id = azurerm_route_table.sp1.id
}
# ──  Route table: Spoke 2 ─────────────────────────────────────────────────────────
resource "azurerm_route_table" "sp2" {
  name                = "rt-${var.prefix}-sp2"
  resource_group_name = var.rg_name
  location            = var.location
  tags                = var.tags
  bgp_route_propagation_enabled = false //"only routes I explicitly define in this table are valid."
}
resource "azurerm_route" "sp2_default"{
  name = "route-default-to-fw"
  resource_group_name = var.rg_name
  route_table_name = azurerm_route_table.sp2.name
  address_prefix = "0.0.0.0/0"
  next_hop_type = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}
//Matches 10.0.0.0/8  → firewall    (user route, 8-bit prefix)
//Matches 10.2.0.0/16 → VNetPeering (system route, 16-bit prefix)
//User-defined routes beat system routes regardless of prefix length
resource "azurerm_route" "sp2_rfc1918"{
  name = "route-rfc1918-to-fw"
  resource_group_name = var.rg_name
  route_table_name = azurerm_route_table.sp2.name
  address_prefix = "10.0.0.0/8"
  next_hop_type = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}

resource "azurerm_subnet_route_table_association" "sp2_rt_association" {
  subnet_id      = var.spoke2_pe_subnet_id
  route_table_id = azurerm_route_table.sp2.id
}


# ─────────────────────────────────────────────────────────────────────────────
# Module: 01_hub_network
# Deploys: Hub, Spoke 1, Spoke 2, all subnets, peerings, NSGs, clinical VM
# 一. nsg locking SSH to macbook's ip only
# 二. a vm to ssh into
# 三. vm gets a sys-assigned managed identity
# SESSION GOAL: Apply this module alone
# Verify peering state = Connected, SSH to VM works, effective routes
# show VNetPeering next hops (no firewall yet).
# ─────────────────────────────────────────────────────────────────────────────

locals {
    hub_fw_subnet_cidr = "10.0.1.0/26"
    hub_dnsr_in_cidr = "10.0.1.64/26"
    hub_dnsr_out_cidr = "10.0.1.128/26"
    spoke1_workload_cidr = "10.1.1.0/24"
    spoke2_pe_cidr = "10.2.1.0/24"
}
# ─────────────────────────────────────────────────────────────────────────────
# hub vnet
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "hub_vnet" {
    name = "vnet-${var.prefix}-hub"
    resource_group_name = var.rg_name
    location = var.location
    address_space = [var.hub_address_space]
    tags = var.tags
    //step1, [] -> default azure dns
    //step3, 10.0.1.X -> private dns
    dns_servers = var.dns_servers
}

//subnet for fw
resource "azurerm_subnet" "hub_fw_subnet" {
    name = "AzureFirewallSubnet" //required naming
    resource_group_name = var.rg_name
    virtual_network_name = azurerm_virtual_network.hub_vnet.name
    address_prefixes = [local.hub_fw_subnet_cidr]
}
//subnet for dns forwarder - inbound dns queries from spokes.
resource "azurerm_subnet" "hub_dnsr_in_subnet" {
    name = "dnsr-in"
    resource_group_name = var.rg_name
    virtual_network_name = azurerm_virtual_network.hub_vnet.name
    address_prefixes = [local.hub_dnsr_in_cidr]
    //必须 delegation -> this subnet is locked for fw private ep only.
    delegation {
        name = "dnsr-in-delegation"
        service_delegation {
        name    = "Microsoft.Network/dnsResolvers"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        }
    }
}
//subnet for dns forwarder - forwarding queries for on-prem domains accoridng to a forwarding ruleset. (northwind.local)
//required for the dns resolver, but not used in this project, since no onprem AD, no ruleset.
resource "azurerm_subnet" "hub_dnsr_out_subnet" {
    name = "dnsr-out"
    resource_group_name = var.rg_name
    virtual_network_name = azurerm_virtual_network.hub_vnet.name
    address_prefixes = [local.hub_dnsr_out_cidr]
    //必须 resolver needs to put a nic here.
    delegation {
        name = "dnsr-out-delegation"
        service_delegation {
        name    = "Microsoft.Network/dnsResolvers"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        }
    }
} 
# ─────────────────────────────────────────────────────────────────────────────
# spoke 1 -> no public inbound [clinical workloads like HL7, Epic, ETL]
# on-prem clinicians need vpn or ER to access.
# All outbound, internal east-west traffic goes to fw and logged
# UDR forces 0.0.0.0/0 and 10.0.0.0/16 through fw
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "spoke1_vnet" {
    name = "vnet-${var.prefix}-spoke1"
    resource_group_name = var.rg_name
    location = var.location
    address_space = [var.spoke1_address_space]
    tags = var.tags
    //either 168.63.129.16 (azure dns) or the private DNS resolver IP.
    //onprem workloads can not use azure dns even with ER.
    //onprem AD -> DNSR (inbound EP) -> azure dns ->DNSR (not outbound EP) -> onprem AD
    dns_servers = var.dns_servers
}
resource "azurerm_subnet" "spoke1_workload_subnet" {
    name = "spoke1-workload-subnet"
    resource_group_name = var.rg_name
    virtual_network_name = azurerm_virtual_network.spoke1_vnet.name
    address_prefixes = [local.spoke1_workload_cidr]
    private_endpoint_network_policies = "Enabled" //If "Disabled", the system route to the PE IP takes precedence over UDR. This is NOT the desired behavior for Private Endpoints.
}
# ─────────────────────────────────────────────────────────────────────────────
# spoke 2 -> shared services, private endpoints.
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "spoke2_vnet" {
    name = "vnet-${var.prefix}-spoke2"
    resource_group_name = var.rg_name
    location = var.location
    address_space = [var.spoke2_address_space]
    tags = var.tags
    dns_servers = var.dns_servers
}
resource "azurerm_subnet" "spoke2_pe_subnet" {
    name = "spoke2-pe-subnet"
    resource_group_name = var.rg_name
    virtual_network_name = azurerm_virtual_network.spoke2_vnet.name
    address_prefixes = [local.spoke2_pe_cidr]
    //decides NSGs and UDRs actually apply to the traffic going to a PE in that subnet.
    private_endpoint_network_policies = "Disabled" //If "Enabled", NSGs and UDRs are enforced on the private endpoint. If "Disabled", the system route to the PE IP takes precedence over UDR. This is the desired behavior for Private Endpoints.
}
# ─────────────────────────────────────────────────────────────────────────────
# peerings - hub to spokes, spokes to hub
# ─────────────────────────────────────────────────────────────────────────────
# hub -> spoke1
resource "azurerm_virtual_network_peering" "hub_to_spoke1" {
    name = "hub-to-spoke1"
    resource_group_name = var.rg_name
    virtual_network_name = azurerm_virtual_network.hub_vnet.name
    remote_virtual_network_id = azurerm_virtual_network.spoke1_vnet.id
    allow_forwarded_traffic = true // allowed to receive packets from the spoke1 that did not originate in the spoke1
    allow_gateway_transit = false
    allow_virtual_network_access = true // Allow hub to initiate communication to the spoke1.
}

# spoke1 -> hub
resource "azurerm_virtual_network_peering" "spoke1_to_hub" {
    name = "spoke1-to-hub"
    resource_group_name =var.rg_name
    virtual_network_name = azurerm_virtual_network.spoke1_vnet.name
    remote_virtual_network_id = azurerm_virtual_network.hub_vnet.id
    allow_forwarded_traffic = true // allowed to receive packets from the Hub that did not originate in the Hub
    allow_virtual_network_access = true // Allows Spoke1 to initiate communication to the Hub.
}
# hub -> spoke2
resource "azurerm_virtual_network_peering" "hub_to_spoke2" {
    name = "hub-to-spoke2"
    resource_group_name = var.rg_name
    virtual_network_name = azurerm_virtual_network.hub_vnet.name
    remote_virtual_network_id = azurerm_virtual_network.spoke2_vnet.id
    allow_forwarded_traffic = true // allowed to receive packets from the spoke2 that did not originate in the spoke2
    allow_gateway_transit = false
    allow_virtual_network_access = true // Allow hub to initiate communication to the spoke2.
}
# spoke2 -> hub
resource "azurerm_virtual_network_peering" "spoke2_to_hub" {
    name = "spoke2-to-hub"
    resource_group_name = var.rg_name
    virtual_network_name = azurerm_virtual_network.spoke2_vnet.name
    remote_virtual_network_id = azurerm_virtual_network.hub_vnet.id
    allow_forwarded_traffic = true // allowed to receive packets from the Hub that did not originate in the Hub
    allow_virtual_network_access = true // Allows Spoke2 to initiate communication to the Hub.
}
# ─────────────────────────────────────────────────────────────────────────────
# NSGs
# ─────────────────────────────────────────────────────────────────────────────
//nsg for spoke1
resource "azurerm_network_security_group" "spoke1" {
  name                = "nsg-${var.prefix}-spoke1"
  resource_group_name = var.rg_name
  location            = var.location
  tags                = var.tags

  security_rule {
    name                       = "allow-ssh-from-admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.mac_pub_ip //later to add
    destination_address_prefix = "*"
  }
}
//associate nsg to spoke1 workload subnet
resource "azurerm_subnet_network_security_group_association" "spoke1_workload" {
    subnet_id = azurerm_subnet.spoke1_workload_subnet.id
    network_security_group_id = azurerm_network_security_group.spoke1.id
}
//nsg for spoke2
resource "azurerm_network_security_group" "spoke2" {
  name                = "nsg-${var.prefix}-spoke2"
  resource_group_name = var.rg_name
  location            = var.location
  tags                = var.tags
  # default deny - Spoke 2 has no public-facing resources, so all inbound traffic is denied by not creating any allow rules.
  # no outbound rules, rely on the firewall to inspect traffic. The firewall will be the only way for Spoke 2 to communicate with other networks. firewall rules will be configured next.
}
//associate nsg to spoke2 pe subnet
resource "azurerm_subnet_network_security_group_association" "spoke2" {
  subnet_id                 = azurerm_subnet.spoke2_pe_subnet.id
  network_security_group_id = azurerm_network_security_group.spoke2.id
}
# -────────────────────────────────────────────────────────────────────────────
# clinical VM in spoke1 for testing connectivity, peering, NSGs, UDRs, and later firewall rules.
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_public_ip" "vm" {
    name = "pip-${var.prefix}-clinical-vm"
    resource_group_name = var.rg_name
    location = var.location
    allocation_method = "Static"
    sku = "Standard" //required for firewall + private endpoints in the same vnet.
    tags = var.tags
}
//nic for the vm, what actually put the vm in the spoke1's subnet.
resource "azurerm_network_interface" "vm" {
    name = "nic-${var.prefix}-clinical-vm"
    resource_group_name = var.rg_name
    location = var.location
    tags = var.tags
    ip_configuration {
        name = "ipconfig1"
        subnet_id = azurerm_subnet.spoke1_workload_subnet.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id = azurerm_public_ip.vm.id
    }
}
//临床 VM, for testing connectivity, peering, NSGs, UDRs, and later firewall rules.
resource "azurerm_linux_virtual_machine" "clinical" {
  name                  = "vm-${var.prefix}-clinical-01"
  resource_group_name   = var.rg_name
  location              = var.location
  size                  = "Standard_B2s_v2"
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.vm.id]
  tags                  = var.tags

  # System-assigned managed identity — used for Key Vault + Service Bus RBAC
  identity {
    type = "SystemAssigned"
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("~/.ssh/id_rsa.pub") #use azure key vault in production.
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}


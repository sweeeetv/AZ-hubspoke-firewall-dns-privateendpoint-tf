output "hub_vnet_id"                    { value = azurerm_virtual_network.hub_vnet.id }
output "hub_vnet_name"                  { value = azurerm_virtual_network.hub_vnet.name }
output "hub_dnsr_inbound_subnet_id"     { value = azurerm_subnet.hub_dnsr_in_subnet.id }
output "hub_dnsr_outbound_subnet_id"    { value = azurerm_subnet.hub_dnsr_out_subnet.id }
output "spoke1_workload_subnet_id"      { value = azurerm_subnet.spoke1_workload_subnet.id }
output "spoke2_pe_subnet_id"            { value = azurerm_subnet.spoke2_pe_subnet.id }
output "spoke1_nsg_id"                  { value = azurerm_network_security_group.spoke1.id }
output "spoke2_nsg_id"                  { value = azurerm_network_security_group.spoke2.id }
output "vm_public_ip"                   { value = azurerm_public_ip.vm.ip_address }
output "vm_private_ip"                  { value = azurerm_network_interface.vm.private_ip_address }
//Without outputting and passing this ID, modules 04 and 06 have no way of knowing which identity to grant access to. They'd have to hardcode a GUID, which breaks every time you recreate the VM.
//The principal ID is what Azure AD assigns to the managed identity
output "vm_principal_id"                { value = azurerm_linux_virtual_machine.clinical.identity[0].principal_id }
//output "vm_id"                        { value = azurerm_linux_virtual_machine.clinical.id }

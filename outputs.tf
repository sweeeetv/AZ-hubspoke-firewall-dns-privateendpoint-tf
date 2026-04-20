# always on ──────────────────────────────────────────────
output "resource_group_name" {
    description = "all the lab resources live"
    value = azurerm_resource_group.main.name
}

output "log_analytics_workspace_id" {
    description = "The ID of the Log Analytics Workpace"
    value = azurerm_log_analytics_workspace.main.id
}
# step1 hub spoke ──────────────────────────────────────────────────
output "vm_public_ip" {
    description = "ssh into here"
    value = module.hub.vm_public_ip
}
output "vm_private_ip" {
    description = "vm's private ip inside spoke1"
    value = module.hub.vm_private_ip
}
output "vm_principal_id" {
    description = "The principal ID of the VM in spoke1 - for RBAC"
    value = module.hub.vm_principal_id
}

# step2 fw ──────────────────────────────────────────────────
# step3 dns ─────────────────────────────────────────────────
# step4 key vault ───────────────────────────────────────────
# step5 storage ─────────────────────────────────────────────
# step6 service bus ──────────────────────────────────────────────
# step7 monitoring ──────────────────────────────────────────────────


# ─────────────────────────────────────────────
# Global
# ─────────────────────────────────────────────
variable "subscription_id" {
  description = "Your Azure subscription ID"
  type        = string
  default     = "bcd4fe40-938d-48e2-bea9-6425a552c4ab"
}
variable "location" {
  type        = string
  default     = "australiasoutheast"
}
variable "prefix" {
    description = "Prefix for all resources"
    type        = string
    default     = "Hospital"
}
variable "tags" {
    description = "A map of tags to add to all resources"
    type        = map(string)
    default     = {
    project ="az700-hub-spoke-firewall-dns"
    }
}
variable "dns_servers" {
  type    = list(string)
  default = []
}
# ─────────────────────────────────────────────
# network block
# ─────────────────────────────────────────────
variable "hub_address_space" {
    type = string
    default = "10.0.0.0/16"
}
variable "spoke1_address_space" {
    description = "?"
    type = string
    default = "10.1.0.0/16"
}
variable "spoke2_address_space" {
    description = "?"
    type = string
    default = "10.2.0.0/16"
}

# ─────────────────────────────────────────────
# VM
# ─────────────────────────────────────────────
variable "admin_username" {
  description = "Admin username for the clinical VM."
  type        = string
  default     = "azureuser"
}
variable "mac_pub_ip" {
  description = "macbook's remote ip for SSH access. Run: curl ifconfig.me"
  type        = string
  
  # No default — must be set in terraform.tfvars“
}

# ─────────────────────────────────────────────
# Feature flags — comment modules in/out in main.tf,
# or use these flags to gate resources within modules.
# ─────────────────────────────────────────────
variable "deploy_firewall" {
  description = "Step 2: Deploy Azure Firewall + UDRs."
  type        = bool
  default     = false 
}

variable "deploy_dns_resolver" {
  description = "Step 3: Deploy DNS Private Resolver + private DNS zones."
  type        = bool
  default     = false
}
 
variable "deploy_key_vault" {
  description = "Step 4: Deploy Key Vault + Private Endpoint."
  type        = bool
  default     = false
}

variable "deploy_storage" {
  description = "Step 5: Deploy Storage account + file share + Private Endpoint."
  type        = bool
  default     = false
}

variable "deploy_service_bus" {
  description = "Step 6: Deploy Service Bus + Private Endpoint."
  type        = bool
  default     = false
}

variable "deploy_monitoring" {
  description = "Step 7: Deploy NSG flow logs + Traffic Analytics."
  type        = bool
  default     = false
}

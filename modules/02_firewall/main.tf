# step 2 firewall : standard Firewall, fw policy, UDRs on spoke subnets.
# diagnostic settings -> LAW
# SESSION GOAL (step 2):
#   Set deploy_firewall = true, apply, then verify:
#   1. `terraform output firewall_private_ip` matches effective route next hop
#   2. SSH still works (SSH goes through NSG, not firewall — this is fine)
#   3. From VM: curl ifconfig.me returns the FIREWALL public IP, not VM pip
#   4. AZFWApplicationRule logs in Log Analytics show the curl request
#
# KEY CONCEPT: Two routes are needed on each spoke route table:
#   - 0.0.0.0/0  → firewall  (internet-bound)
#   - 10.0.0.0/8 → firewall  (east-west / spoke-to-spoke)
#   Without the second route, spoke-to-spoke traffic uses VNet peering
#   direct path and BYPASSES the firewall entirely. This is the #1 gotcha.
# ───────────────────────────────────────────────────


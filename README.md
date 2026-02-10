# openSONIC

# How to jumpstart single Cloudstack management host with KVM nodes as hypervisor hosts

# Set of scripts that prepare "Deployer" machine which will provide services: DHCP, tftp, www and all necessary config files for automated deployment of single Cloudstack host and KVM hypervisors
# Deployer VM needs 8GB RAM and 4 vCPUs
# PXE server will offer boot menus for deploying both Cloudstack Management VM and KVM hosts
# Web and tftp services expose contents of Rocky Linux ISO and kickstarts used for deployments
# 
# Tested to run well on VMs running Rocky Linux 9.x
# 


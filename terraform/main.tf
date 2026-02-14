terraform {
  required_providers {
    cloudstack = {
      source  = "cloudstack/cloudstack"
      version = "~> 0.4"
    }
  }
  required_version = ">= 1.0"
}

provider "cloudstack" {
  api_url    = var.cloudstack_api_url
  api_key    = var.cloudstack_api_key
  secret_key = var.cloudstack_secret_key
}

# Create a VM instance on CloudStack
resource "cloudstack_instance" "vm" {
  name             = var.vm_name
  service_offering = var.service_offering
  template         = var.template_name
  zone             = var.zone_name
  network          = var.network_name

  # Immediately delete the VM when destroyed (no graceful shutdown)
  expunge = true

  tags = {
    environment = var.environment
    project     = "opensonic"
  }
}

output "instance_ip" {
  value       = cloudstack_instance.vm.nic[0].ipaddress
  description = "The IP address of the created instance"
}

output "instance_name" {
  value       = cloudstack_instance.vm.name
  description = "The name of the created instance"
}

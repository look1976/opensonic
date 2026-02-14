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

# Register Rocky Linux 9 template
resource "cloudstack_template" "rocky_linux_9" {
  name             = var.template_name
  display_text     = var.template_display_text
  url              = var.template_url
  zone             = var.zone_id
  os_type          = var.os_type_id
  hypervisor       = var.hypervisor
  format           = var.template_format
  is_public        = var.is_public
  is_featured      = var.is_featured
  is_dynamically_scalable = var.is_dynamically_scalable
  password_enabled = var.password_enabled
  requires_hvm     = var.requires_hvm

  tags = {
    os       = "Rocky Linux 9"
    project  = "opensonic"
    managed  = "terraform"
  }
}

output "template_id" {
  value       = cloudstack_template.rocky_linux_9.id
  description = "The ID of the registered template"
}

output "template_name" {
  value       = cloudstack_template.rocky_linux_9.name
  description = "The name of the registered template"
}

output "template_url" {
  value       = cloudstack_template.rocky_linux_9.url
  description = "The URL of the template image"
}

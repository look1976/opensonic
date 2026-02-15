variable "cloudstack_api_url" {
  description = "The URL of the CloudStack API endpoint"
  type        = string
  default     = "http://cloudstack.home.lab:8080/client/api"
}

variable "cloudstack_api_key" {
  description = "API key for CloudStack authentication"
  type        = string
  sensitive   = true
}

variable "cloudstack_secret_key" {
  description = "Secret key for CloudStack authentication"
  type        = string
  sensitive   = true
}

variable "vm_name" {
  description = "Name of the VM instance to create"
  type        = string
  default     = "opensonic-vm"
}

variable "service_offering" {
  description = "Service offering (VM size/flavor) to use"
  type        = string
  default     = "small"
}

variable "template_name" {
  description = "Template or ISO image to use for the VM"
  type        = string
  default     = "CentOS 7 x86_64"
}

variable "zone_name" {
  description = "CloudStack zone where the VM will be created"
  type        = string
}

variable "network_id" {
  description = "CloudStack network ID (UUID) to attach the VM to"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.network_id))
    error_message = "network_id must be a CloudStack network UUID (not a network name)."
  }
}

variable "environment" {
  description = "Environment tag for the VM instance"
  type        = string
  default     = "development"
}

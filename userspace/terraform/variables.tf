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

variable "network_name" {
  description = "Network to attach the VM to"
  type        = string
}

variable "environment" {
  description = "Environment tag for the VM instance"
  type        = string
  default     = "development"
}

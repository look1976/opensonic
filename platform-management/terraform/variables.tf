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

variable "template_name" {
  description = "Name of the template"
  type        = string
  default     = "Rocky-Linux-9"
}

variable "template_display_text" {
  description = "Display text for the template in UI"
  type        = string
  default     = "Rocky Linux 9"
}

variable "template_url" {
  description = "URL of the template image file (ISO or OVA)"
  type        = string
  # Example: "http://example.com/rocky-linux-9.qcow2"
}

variable "zone_id" {
  description = "Zone ID where the template will be registered"
  type        = string
  # Use CloudStack Zone ID, e.g., zone1
}

variable "os_type_id" {
  description = "OS Type ID for the template"
  type        = string
  # Find available OS types using CloudStack API or console
  # Example: "8edf0db3-7a8e-4cd6-b1c8-cf06aa956a89" for Rocky Linux
}

variable "hypervisor" {
  description = "Hypervisor type (KVM, Xen, VMware, Hyper-V, etc.)"
  type        = string
  default     = "KVM"
}

variable "template_format" {
  description = "Template format (QCOW2, VHD, OVA, VHDX, RAW, etc.)"
  type        = string
  default     = "QCOW2"
}

variable "is_public" {
  description = "Whether the template is available to all users"
  type        = bool
  default     = false
}

variable "is_featured" {
  description = "Whether the template is featured in the UI"
  type        = bool
  default     = false
}

variable "is_dynamically_scalable" {
  description = "Whether the template supports dynamic scaling"
  type        = bool
  default     = true
}

variable "password_enabled" {
  description = "Whether CloudStack can set password for VMs created from this template"
  type        = bool
  default     = true
}

variable "requires_hvm" {
  description = "Whether the template requires HVM"
  type        = bool
  default     = false
}

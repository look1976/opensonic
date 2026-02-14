# Template Registration on CloudStack

This Terraform configuration allows you to register a new template (Rocky Linux 9) on CloudStack 4.22.

## Prerequisites

- Terraform >= 1.0
- CloudStack Terraform provider
- Access to CloudStack API (cloudstack.home.lab)
- Template image file (QCOW2, VHD, OVA, etc.) hosted on a web server accessible to CloudStack
- CloudStack credentials (API key and secret key)

## Getting Started

### 1. Prepare the template image

Download Rocky Linux 9 image from the official site:

```bash
wget https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9.x-GenericCloud.latest.x86_64.qcow2
```

Host the image on a web server accessible to your CloudStack installation.

### 2. Get required IDs from CloudStack

Before configuration, get these IDs from your CloudStack system:

**Find Zone ID:**
```bash
cmk listZones
```

**Find OS Type ID for Rocky Linux:**
```bash
cmk listOsTypes filter=description~Rocky
```

If Rocky Linux is not available, you can use a similar OS type like CentOS.

### 3. Set up configuration

Copy the example file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and fill in:
- `cloudstack_api_key` - Your CloudStack API key
- `cloudstack_secret_key` - Your CloudStack secret key
- `template_url` - URL to the Rocky Linux 9 QCOW2 image
- `zone_id` - CloudStack Zone ID
- `os_type_id` - OS Type ID from CloudStack
- `template_name` - Template name (e.g., "Rocky-Linux-9")
- `hypervisor` - Hypervisor type (KVM, Xen, VMware, etc.)
- `template_format` - Image format (QCOW2, VHD, OVA, etc.)

### 4. Initialize Terraform

```bash
cd platform-management
terraform init
```

### 5. Review the plan

```bash
terraform plan
```

### 6. Apply the configuration

```bash
terraform apply
```

The template will be registered on CloudStack and will appear in the Templates section of the management console.

## Configuration structure

- `main.tf` - Main configuration with provider and template resource
- `variables.tf` - Variable definitions for template configuration
- `terraform.tfvars.example` - Example variable values
- `terraform.tfvars` - Your variable values (do not commit to git)

## Important Notes

- Ensure the template image URL is accessible from CloudStack management server
- Template registration can take time depending on the image size
- Once registered, you can use the template to create new VMs
- Keep `terraform.tfvars` in `.gitignore` to avoid committing sensitive data
- The template is initially private (is_public = false) - change to true if you want all users to access it

## Destroy the template

```bash
terraform destroy
```

This will unregister the template from CloudStack.

## Using the template

After registration, you can reference this template in other Terraform configurations:

```hcl
resource "cloudstack_instance" "vm" {
  name             = "my-vm"
  service_offering = "small"
  template         = "Rocky-Linux-9"  # Use the template name
  zone             = "zone1"
  network          = "guestnetwork"
}
```

## Useful CloudStack Commands

List available templates:
```bash
cmk listTemplates templatefilter=executable
```

List OS types:
```bash
cmk listOsTypes
```

Delete template:
```bash
cmk deleteTemplate id=<template-id>
```

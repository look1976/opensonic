# CloudStack Terraform Configuration

This Terraform configuration allows you to create a virtual machine on CloudStack 4.22.

## Requirements

- Terraform >= 1.0
- CloudStack Terraform provider
- Access to CloudStack API (cloudstack.home.lab)
- CloudStack API credentials (API key and secret key)

## Configuration

### 1. Set up variables

Copy the example configuration file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

### 2. Configure terraform.tfvars

Edit `terraform.tfvars` and fill in:
- `cloudstack_api_key` - Your CloudStack API key
- `cloudstack_secret_key` - Your CloudStack secret key
- `zone_name` - Name of the CloudStack zone
- `network_id` - ID (UUID) of the network
- `service_offering` - VM type/flavor (small, medium, large, etc.)
- `template_name` - Name of the template or ISO image

You can find available templates, zones, and networks in the CloudStack management console.
`network_id` must be the network UUID, not the network name.

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Review the plan

```bash
terraform plan
```

### 5. Apply the configuration

```bash
terraform apply
```

## Configuration structure

- `main.tf` - Main configuration with provider and resources
- `variables.tf` - Variable definitions
- `terraform.tfvars.example` - Example variable values
- `terraform.tfvars` - Your variable values (do not commit to git)

## Notes

- Ensure `terraform.tfvars` is added to `.gitignore` to avoid committing sensitive data
- Adjust the API URL if CloudStack uses a different port than the default 8080
- The `expunge = true` setting causes the VM to be immediately deleted when running `terraform destroy`

## Destroy the VM

```bash
terraform destroy
```

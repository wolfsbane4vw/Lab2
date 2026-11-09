variable "aws_region" {
  description = "AWS region. should match the AMI"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Prefix and Project tag for Lab2 resources."
  type        = string
  default     = "lab2"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.project_name))
    error_message = "Use 2-20 lowercase letters, numbers or hyphens, starting with a letter."
  }
}

variable "ami_id" {
  description = "Base AMI built in Lab1."
  type        = string

  validation {
    condition     = can(regex("^ami-([0-9a-f]{8}|[0-9a-f]{17})$", var.ami_id))
    error_message = "Set ami_id to a valid AMI ID from Lab1's Packer build."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the test server."
  type        = string
  default     = "t3.small"
}

variable "ssh_cidr" {
  description = "Your public IPv4 address with /32, set in terraform.tfvars."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.ssh_cidr)) && can(regex("/32$", var.ssh_cidr))
    error_message = "Set ssh_cidr to your public IPv4 address followed by /32."
  }
}

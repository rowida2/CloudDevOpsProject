variable "region" { default = "eu-central-1" }
variable "project_name" { default = "ivolve" }

variable "ami_id" {
  description = "Ubuntu 22.04 AMI for the region"
  type        = string
  default     = "ami-0000000000000000a"
}

variable "key_name" {
  type    = string
  default = "ivolve-key"
}

variable "allowed_ssh_cidr" {
  description = "Your public IP/32"
  type        = string
  default     = "0.0.0.0/0"
}
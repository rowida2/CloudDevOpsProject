variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  description = "Public subnet for Jenkins"
  type        = string
}

variable "ami_id" {
  description = "Ubuntu 22.04 AMI (differs per region)"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "key_name" {
  description = "Name of the EC2 key pair for SSH"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "Your public IP in CIDR form, e.g. 1.2.3.4/32"
  type        = string
}
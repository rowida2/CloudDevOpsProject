variable "project_name" { type = string }
variable "vpc_cidr" { type = string }
variable "cluster_name" { type = string }

variable "azs" {
  description = "Availability zones (2 required for EKS)"
  type        = list(string)
}

variable "public_subnet_cidrs" { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }
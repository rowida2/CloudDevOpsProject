variable "project_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "private_subnet_ids" {
  description = "Worker nodes go here (2 subnets in 2 AZs)"
  type        = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_count" {
  type    = number
  default = 2
}
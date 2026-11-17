variable "project_name" {
  type = string
}

variable "repository_names" {
  description = "One ECR repository per microservice"
  type        = list(string)
}
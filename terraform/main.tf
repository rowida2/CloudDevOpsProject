terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    bucket         = "ivolve-tfstate-CHANGE-ME"
    key            = "cloud-devops/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "ivolve-tf-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

module "network" {
  source               = "./modules/network"
  project_name         = var.project_name
  cluster_name         = "${var.project_name}-eks"
  vpc_cidr             = "10.0.0.0/16"
  azs                  = ["${var.region}a", "${var.region}b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
}

module "ecr" {
  source           = "./modules/ecr"
  project_name     = var.project_name
  repository_names = ["frontend", "auth-service", "roadmap-service"]
}

module "server" {
  source           = "./modules/server"
  project_name     = var.project_name
  vpc_id           = module.network.vpc_id
  subnet_id        = module.network.public_subnet_ids[0]
  ami_id           = var.ami_id
  key_name         = var.key_name
  allowed_ssh_cidr = var.allowed_ssh_cidr
}



module "eks" {
  source             = "./modules/eks"
  project_name       = var.project_name
  cluster_name       = "${var.project_name}-eks"
  private_subnet_ids = module.network.private_subnet_ids
  public_subnet_ids  = module.network.public_subnet_ids
}
terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "tfstate-web-platform-pojava-101992522685-eu-central-1"
    key            = "environments/dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "tfstate-locks-web-platform-101992522685"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# Networking Module
module "networking" {
  source               = "../../modules/networking"
  name                 = var.name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# Compute Module
module "compute" {
  source             = "../../modules/compute"
  name               = var.name
  environment        = var.environment
  instance_type      = var.instance_type
  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnets
  private_subnet_ids = module.networking.private_subnets
  app_sg_id          = module.networking.app_sg
  alb_sg_id          = module.networking.alb_sg
  max_size           = var.max_size
  min_size           = var.min_size
  desired_capacity   = var.desired_capacity
}

# Database Module
module "database" {
  source             = "../../modules/database"
  name               = var.name
  environment        = var.environment
  private_subnet_ids = module.networking.private_subnets
  security_group_ids = [module.networking.app_sg]
  db_username        = var.db_username
  db_password        = var.db_password
}

# Monitoring Module
module "monitoring" {
  source      = "../../modules/monitoring"
  name        = var.name
  environment = var.environment
  alert_email = var.alert_email
  asg_name    = module.compute.asg_name
}

# Outputs
output "alb_dns_name" {
  value = module.compute.alb_dns_name
}

output "asg_name" {
  value = module.compute.asg_name
}

output "db_endpoint" {
  value = module.database.db_endpoint
}

output "sns_topic_arn" {
  value = module.monitoring.sns_topic_arn
}

# rewrite_clean_repo.ps1
# Overwrite core Terraform module + env files with a consistent, minimal, working layout.
# Runs from repo root: C:\projects\terraform-web-platform

$base = "C:\projects\terraform-web-platform"

# Helper: write file (creates folder if needed)
function Write-RepoFile($path, $content) {
  $full = Join-Path $base $path
  $dir = Split-Path $full -Parent
  if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
  $content | Out-File -FilePath $full -Encoding utf8 -Force
  Write-Host "Wrote $path"
}

### ---------------------------
### modules/networking
### ---------------------------
Write-RepoFile "modules/networking/variables.tf" @'
variable "name" {
  type        = string
  description = "Project name/prefix"
}

variable "environment" {
  type        = string
  description = "Environment name (dev/prod)"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
}

variable "azs" {
  type        = list(string)
  description = "List of AZs to create subnets in"
}
'@

Write-RepoFile "modules/networking/main.tf" @'
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "${var.name}-${var.environment}-vpc"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags = { Name = "${var.name}-${var.environment}-igw" }
}

# Create public subnets (one per AZ)
resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "${var.name}-${var.environment}-public-${count.index + 1}"
    Environment = var.environment
  }
}

# Create private subnets (one per AZ)
resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + length(var.azs))
  availability_zone = var.azs[count.index]
  tags = {
    Name        = "${var.name}-${var.environment}-private-${count.index + 1}"
    Environment = var.environment
  }
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.name}-${var.environment}-public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Minimal security group for app servers (allow from ALB later)
resource "aws_security_group" "app" {
  name        = "${var.name}-${var.environment}-app-sg"
  description = "Allow inbound from ALB, allow outbound"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name}-${var.environment}-app-sg"
    Environment = var.environment
  }
}

# Security group for ALB (allow HTTP)
resource "aws_security_group" "alb" {
  name        = "${var.name}-${var.environment}-alb-sg"
  description = "Allow HTTP from internet"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-${var.environment}-alb-sg" }
}
'@

Write-RepoFile "modules/networking/outputs.tf" @'
output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnets" {
  value = aws_subnet.public[*].id
}

output "private_subnets" {
  value = aws_subnet.private[*].id
}

output "app_sg_id" {
  value = aws_security_group.app.id
}

output "alb_sg_id" {
  value = aws_security_group.alb.id
}
'@

### ---------------------------
### modules/compute
### Minimal ALB + Launch Template + ASG that uses the networking outputs
### ---------------------------
Write-RepoFile "modules/compute/variables.tf" @'
variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "ami_id" {
  type = string
  description = "AMI for instances"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "app_sg_id" {
  type = string
}

variable "alb_sg_id" {
  type = string
}

variable "desired_capacity" {
  type    = number
  default = 1
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 2
}
'@

Write-RepoFile "modules/compute/main.tf" @'
locals {
  user_data = <<-EOF
              #!/bin/bash
              echo "Hello from ${var.name}-${var.environment}" > /var/www/html/index.html
              yum install -y httpd
              systemctl enable httpd
              systemctl start httpd
              EOF
}

resource "aws_launch_template" "lt" {
  name_prefix   = "${var.name}-${var.environment}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "alb" {
  name               = "${var.name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_sg_id]
  tags = { Name = "${var.name}-${var.environment}-alb" }
}

resource "aws_lb_target_group" "tg" {
  name     = "${var.name}-${var.environment}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = cidrsubnet(var.public_subnet_ids[0],0,0) # placeholder not used by AWS; keep vpc deduced by ALB
  target_type = "instance"
  health_check {
    path = "/"
    matcher = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_autoscaling_group" "asg" {
  name                      = "${var.name}-${var.environment}-asg"
  max_size                  = var.max_size
  min_size                  = var.min_size
  desired_capacity          = var.desired_capacity
  vpc_zone_identifier       = var.private_subnet_ids
  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }
  target_group_arns         = [aws_lb_target_group.tg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 60

  tag {
    key                 = "Name"
    value               = "${var.name}-${var.environment}-instance"
    propagate_at_launch = true
  }
}
'@

Write-RepoFile "modules/compute/outputs.tf" @'
output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}

output "asg_name" {
  value = aws_autoscaling_group.asg.name
}
'@

### ---------------------------
### modules/database
### RDS single instance minimal
### ---------------------------
Write-RepoFile "modules/database/variables.tf" @'
variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "db_password" {
  type    = string
  sensitive = true
}
'@

Write-RepoFile "modules/database/main.tf" @'
resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "${var.name}-${var.environment}-db-subnet-group"
    Environment = var.environment
  }
}

resource "aws_db_instance" "this" {
  identifier             = "${var.name}-${var.environment}-db"
  engine                 = "mysql"
  allocated_storage      = 20
  instance_class         = "db.t3.micro"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  skip_final_snapshot    = true

  tags = {
    Name        = "${var.name}-${var.environment}-db"
    Environment = var.environment
  }
}
'@

Write-RepoFile "modules/database/outputs.tf" @'
output "db_endpoint" {
  value = aws_db_instance.this.endpoint
}

output "db_id" {
  value = aws_db_instance.this.id
}
'@

### ---------------------------
### modules/monitoring
### ---------------------------
Write-RepoFile "modules/monitoring/variables.tf" @'
variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alert_email" {
  type    = string
  default = ""
}

variable "asg_name" {
  type    = string
  default = ""
}
'@

Write-RepoFile "modules/monitoring/main.tf" @'
resource "aws_sns_topic" "alerts" {
  name = "${var.name}-${var.environment}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "asg_cpu_high" {
  count               = var.asg_name != "" ? 1 : 0
  alarm_name          = "${var.name}-${var.environment}-asg-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
}
'@

Write-RepoFile "modules/monitoring/outputs.tf" @'
output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
'@

### ---------------------------
### environments/dev
### ---------------------------
Write-RepoFile "environments/dev/variables.tf" @'
variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "name" {
  type    = string
  default = "web-platform"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["eu-central-1a", "eu-central-1b"]
}

variable "ami_id" {
  type    = string
  default = ""   # set to a valid AMI for your region (or pass via CLI)
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_password" {
  type    = string
  default = "ChangeMe123!"
  sensitive = true
}

variable "alert_email" {
  type    = string
  default = ""
}
'@

Write-RepoFile "environments/dev/main.tf" @'
terraform {
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

module "networking" {
  source      = "../../modules/networking"
  name        = var.name
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  azs         = var.azs
}

module "compute" {
  source             = "../../modules/compute"
  name               = var.name
  environment        = var.environment
  ami_id             = var.ami_id
  instance_type      = var.instance_type
  public_subnet_ids  = module.networking.public_subnets
  private_subnet_ids = module.networking.private_subnets
  app_sg_id          = module.networking.app_sg_id
  alb_sg_id          = module.networking.alb_sg_id
  desired_capacity   = 1
  min_size           = 1
  max_size           = 2
}

module "database" {
  source             = "../../modules/database"
  name               = var.name
  environment        = var.environment
  private_subnet_ids = module.networking.private_subnets
  security_group_ids = [module.networking.app_sg_id]
  db_username        = "admin"
  db_password        = var.db_password
}

module "monitoring" {
  source        = "../../modules/monitoring"
  name          = var.name
  environment   = var.environment
  alert_email   = var.alert_email
  asg_name      = module.compute.asg_name
}
'@

Write-RepoFile "environments/dev/outputs.tf" @'
output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnets" {
  value = module.networking.public_subnets
}

output "alb_dns" {
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
'@

### ---------------------------
### environments/prod - minimal example (copy of dev with prod defaults)
### ---------------------------
Write-RepoFile "environments/prod/variables.tf" @'
variable "aws_region" { type = string default = "eu-central-1" }
variable "name" { type = string default = "web-platform" }
variable "environment" { type = string default = "prod" }
variable "vpc_cidr" { type = string default = "10.20.0.0/16" }
variable "azs" { type = list(string) default = ["eu-central-1a","eu-central-1b"] }
variable "ami_id" { type = string default = "" }
variable "instance_type" { type = string default = "t3.small" }
variable "db_password" { type = string default = "ProdChangeMe!" sensitive = true }
variable "alert_email" { type = string default = "" }
'@

Write-RepoFile "environments/prod/main.tf" @'
terraform {
  backend "s3" {
    bucket         = "tfstate-web-platform-pojava-101992522685-eu-central-1"
    key            = "environments/prod/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "tfstate-locks-web-platform-101992522685"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

module "networking" {
  source      = "../../modules/networking"
  name        = var.name
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  azs         = var.azs
}

module "compute" {
  source             = "../../modules/compute"
  name               = var.name
  environment        = var.environment
  ami_id             = var.ami_id
  instance_type      = var.instance_type
  public_subnet_ids  = module.networking.public_subnets
  private_subnet_ids = module.networking.private_subnets
  app_sg_id          = module.networking.app_sg_id
  alb_sg_id          = module.networking.alb_sg_id
  desired_capacity   = 2
  min_size           = 1
  max_size           = 4
}

module "database" {
  source             = "../../modules/database"
  name               = var.name
  environment        = var.environment
  private_subnet_ids = module.networking.private_subnets
  security_group_ids = [module.networking.app_sg_id]
  db_username        = "admin"
  db_password        = var.db_password
}

module "monitoring" {
  source        = "../../modules/monitoring"
  name          = var.name
  environment   = var.environment
  alert_email   = var.alert_email
  asg_name      = module.compute.asg_name
}
'@

Write-RepoFile ".gitignore" @'
.terraform/
terraform.tfstate
terraform.tfstate.backup
*.tfvars
*.zip
'@

Write-Host "REWRITE COMPLETE. Now run the usual terraform commands in environments/dev:"
Write-Host "cd $base\environments\dev"
Write-Host "terraform init -reconfigure"
Write-Host "terraform validate"
Write-Host "terraform plan"

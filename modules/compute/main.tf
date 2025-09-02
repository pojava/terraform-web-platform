###############################
# Locals
###############################
locals {
  user_data = <<-EOF
    #!/bin/bash
    echo "Hello from ${var.name}-${var.environment}" > /var/www/html/index.html
    yum install -y httpd
    systemctl enable httpd
    systemctl start httpd
  EOF
}

###############################
# Data Source: Latest Amazon Linux 2 AMI
###############################
data "aws_ami" "latest_amzn2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

###############################
# Launch Template
###############################
resource "aws_launch_template" "lt" {
  name_prefix   = "${var.name}-${var.environment}-lt-"
  image_id      = data.aws_ami.latest_amzn2.id
  instance_type = var.instance_type
  user_data     = base64encode(local.user_data)

  lifecycle {
    create_before_destroy = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name}-${var.environment}-instance"
    }
  }
}

###############################
# Application Load Balancer
###############################
resource "aws_lb" "alb" {
  name               = "${var.name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_sg_id]

  tags = {
    Name = "${var.name}-${var.environment}-alb"
  }
}

###############################
# Target Group
###############################
resource "aws_lb_target_group" "tg" {
  name        = "${var.name}-${var.environment}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"
}

###############################
# ALB Listener
###############################
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

###############################
# Auto Scaling Group
###############################
resource "aws_autoscaling_group" "asg" {
  name                      = "${var.name}-${var.environment}-asg"
  max_size                  = var.max_size
  min_size                  = var.min_size
  desired_capacity          = var.desired_capacity
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = [aws_lb_target_group.tg.arn]

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 60

  tag {
    key                 = "Name"
    value               = "${var.name}-${var.environment}-instance"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

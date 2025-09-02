resource "aws_db_subnet_group" "db_subnets" {
  name       = "${var.name}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.name}-${var.environment}-db-subnet-group"
  }
}

resource "aws_db_instance" "this" {
  identifier             = "${var.name}-${var.environment}-db"
  allocated_storage      = var.allocated_storage
  engine                 = var.engine
  engine_version         = var.engine_version
  instance_class         = var.instance_class
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids = var.security_group_ids
  multi_az               = var.multi_az
  publicly_accessible    = false
  skip_final_snapshot    = true
  apply_immediately      = true

  tags = {
    Name        = "${var.name}-${var.environment}-db"
    Environment = var.environment
  }
}

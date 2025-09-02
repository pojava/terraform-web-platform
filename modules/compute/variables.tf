variable "name" {}
variable "environment" {}
# variable "ami_id" {}
variable "instance_type" {}
variable "vpc_id" {}
variable "public_subnet_ids" {
  type = list(string)
}
variable "private_subnet_ids" {
  type = list(string)
}
variable "app_sg_id" {}
variable "alb_sg_id" {}
variable "max_size" {
  type = number
}
variable "min_size" {
  type = number
}
variable "desired_capacity" {
  type = number
}

terraform {
  backend "s3" {
    bucket         = "tfstate-web-platform-youraccount-eu-central-1"
    key            = "dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "tfstate-locks-web-platform-youraccount"
    encrypt        = true
  }
}
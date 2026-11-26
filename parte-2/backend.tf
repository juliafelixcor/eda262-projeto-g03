terraform {
  backend "s3" {
    bucket         = "eda262-g03-terraform-state"
    key            = "parte-2/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "eda262-g03-terraform-locks"
    encrypt        = true
  }
}

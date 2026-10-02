module "data_lake" {
  source = "./modules/data-lake"

  aws_region = var.aws_region
}
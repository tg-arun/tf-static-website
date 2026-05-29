# Your main region — where S3 will live
provider "aws" {
  region = var.aws_region
}

# ACM certificates for CloudFront MUST be created in us-east-1
# This is an AWS rule, not a Terraform rule — CloudFront is a global
# service that only reads certs from us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

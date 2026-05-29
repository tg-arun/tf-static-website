variable "aws_region" {
  description = "AWS region for S3 and most resources"
  type        = string
  default     = "ap-south-1"
}

variable "domain_name" {
  description = "Your domain, e.g. myportfolio.com"
  type        = string
}

variable "project_name" {
  description = "Short name used in resource naming"
  type        = string
  default     = "my-static-site"
}

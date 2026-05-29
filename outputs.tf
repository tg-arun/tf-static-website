output "cloudfront_url" {
  description = "CloudFront URL — works even before DNS propagates"
  value       = "https://${aws_cloudfront_distribution.website.domain_name}"
}

output "website_url" {
  description = "Your custom domain URL"
  value       = "https://${var.domain_name}"
}

output "s3_bucket_name" {
  description = "S3 bucket where your files live"
  value       = aws_s3_bucket.website.bucket
}

output "cloudfront_distribution_id" {
  description = "Needed if you want to invalidate the cache later"
  value       = aws_cloudfront_distribution.website.id
}

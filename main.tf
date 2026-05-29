# ─────────────────────────────────────────────
# 1. Route53 — the hosted zone for your domain
# ─────────────────────────────────────────────
# A "hosted zone" is like a folder in AWS for all your DNS records.
# If you bought your domain on Route53, this zone already exists —
# use a data source to look it up instead of creating a new one.
# We're creating it fresh here for learning purposes.

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# ─────────────────────────────────────────────
# 2. ACM Certificate — HTTPS for your domain
# ─────────────────────────────────────────────
# We use provider = aws.us_east_1 here because CloudFront
# requires it. This is the most common beginner mistake in
# this project — if you forget alias, CloudFront will reject
# the cert even though it looks valid.

resource "aws_acm_certificate" "cert" {
  provider = aws.us_east_1 # <-- CRITICAL: must be us-east-1

  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"

  # lifecycle rule: create the new cert before destroying the old one
  # this prevents downtime during cert renewal
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Project = var.project_name
  }
}

# ─────────────────────────────────────────────
# 3. DNS validation records for ACM
# ─────────────────────────────────────────────
# When ACM issues a cert, it needs to verify you own the domain.
# It does this by asking you to add a special DNS TXT record.
# This block does that automatically.
#
# for_each here: ACM may give you multiple validation records
# (one per domain in subject_alternative_names). We loop over all.

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# This resource WAITS until AWS confirms the cert is validated.
# Terraform will pause here — sometimes 2-5 minutes — until done.
resource "aws_acm_certificate_validation" "cert" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ─────────────────────────────────────────────
# 4. S3 bucket — stores your website files
# ─────────────────────────────────────────────
# Key learning point: we do NOT enable public access on this bucket.
# Only CloudFront can read it. This is the modern, secure pattern.
# The old way (public S3 + static hosting) is deprecated.

resource "aws_s3_bucket" "website" {
  bucket = "${var.project_name}-website-${random_id.suffix.hex}"

  tags = {
    Project = var.project_name
  }
}

# Generates a random 4-char suffix so your bucket name is globally unique.
# S3 bucket names must be unique across ALL AWS accounts worldwide.
resource "random_id" "suffix" {
  byte_length = 4
}

# Block ALL public access — we want only CloudFront to read this
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning — if you upload a bad index.html, you can roll back
resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Upload your website's index.html to S3
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  source       = "${path.module}/website/index.html"
  content_type = "text/html"

  # etag: Terraform re-uploads the file only when its content changes
  etag = filemd5("${path.module}/website/index.html")
}

# ─────────────────────────────────────────────
# 5. OAC — Origin Access Control
# ─────────────────────────────────────────────
# OAC is what allows CloudFront to read your private S3 bucket.
# It's a signed identity that S3 trusts. Without this, CloudFront
# would get a 403 Access Denied from S3.

resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for ${var.domain_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ─────────────────────────────────────────────
# 6. S3 Bucket Policy — only allow CloudFront
# ─────────────────────────────────────────────
# This policy says: "only the specific CloudFront distribution
# above can read objects in this bucket"

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            # Only THIS CloudFront distribution can access this bucket
            "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
          }
        }
      }
    ]
  })
}

# ─────────────────────────────────────────────
# 7. CloudFront distribution
# ─────────────────────────────────────────────
# CloudFront is AWS's CDN. It caches your files in ~450 edge
# locations worldwide so users get fast responses regardless
# of where they are.

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  default_root_object = "index.html" # serve index.html when user hits /
  aliases             = [var.domain_name, "www.${var.domain_name}"]
  price_class         = "PriceClass_100" # only US/Europe/Asia — cheapest option
  comment             = "${var.project_name} website"

  # Where CloudFront fetches files from (your S3 bucket)
  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "s3-website-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  # Default behaviour: how to handle most requests
  default_cache_behavior {
    target_origin_id       = "s3-website-origin"
    viewer_protocol_policy = "redirect-to-https" # HTTP → HTTPS automatically
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true # gzip/brotli compression — faster page loads

    forwarded_values {
      query_string = false # don't pass query strings to S3 (not needed)
      cookies {
        forward = "none"
      }
    }

    # Cache for 1 day in browsers, 1 week in CloudFront edge nodes
    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 604800
  }

  # HTTPS settings — use the cert we created in ACM
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert.certificate_arn
    ssl_support_method       = "sni-only" # cheaper than dedicated IP
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # Required block — "no restrictions, serve to everyone"
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Project = var.project_name
  }
}

# ─────────────────────────────────────────────
# 8. Route53 DNS records → point domain to CloudFront
# ─────────────────────────────────────────────
# An "A record alias" in Route53 is special — it's free (no per-query
# charge) and lets you point a root domain (like example.com, not just
# www.example.com) at an AWS resource like CloudFront.

resource "aws_route53_record" "root" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

# www subdomain → same CloudFront distribution
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

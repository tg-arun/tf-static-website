# tf-static-website

> Static website hosting on AWS, fully automated with Terraform.

Live site: **[threadsofbharat.store](https://threadsofbharat.store)**

---

## Architecture

User → Route53 (DNS) → CloudFront (CDN + HTTPS) → S3 (private bucket)
↕
ACM Certificate
(us-east-1)


| Layer | Service | Purpose |
|---|---|---|
| DNS | Route53 | Resolves domain to CloudFront |
| CDN | CloudFront | Global caching, HTTPS termination |
| TLS | ACM | Free SSL certificate, auto-renewed |
| Storage | S3 | Private bucket, stores website files |

---

## What I built

- **Private S3 bucket** — website files are not publicly accessible. Only CloudFront can read them via Origin Access Control (OAC)
- **CloudFront distribution** — serves the site from 450+ edge locations worldwide with gzip/brotli compression
- **ACM SSL certificate** — HTTPS on a custom domain with automatic DNS validation via Route53
- **Route53 alias records** — root domain and www both point to CloudFront (alias A records, not CNAME — free and supports root domains)
- **S3 versioning** — every upload is versioned so bad deploys can be rolled back

---

## Key things I learned

- ACM certificates for CloudFront **must** be created in `us-east-1` regardless of where your other resources live — CloudFront is a global service that only reads certs from that region. This requires a second provider block with an alias in Terraform.
- The modern pattern is a **private S3 bucket + OAC**, not a public bucket with static website hosting enabled. The old public bucket pattern is deprecated.
- `for_each` on ACM validation records — ACM returns one DNS record per domain in `subject_alternative_names`. Using `for_each` loops over all of them automatically instead of hardcoding each one.
- **Alias A records vs CNAME** — alias records are free (no per-query charge), resolve faster, and work on root domains (CNAME cannot be used on a root domain like `example.com`).
- Terraform `data` sources — used to look up the existing Route53 hosted zone instead of creating a new one, which would have changed the nameservers.
- **`terraform plan` before every apply** — the plan showed exactly what would be created/changed before any real AWS resources were touched.

---

## Prerequisites

- Terraform >= 1.6
- AWS CLI configured (`aws configure`)
- A registered domain with nameservers pointed at Route53

---

## Project structure

tf-static-website/
├── main.tf                    # All AWS resources
├── variables.tf               # Input variable definitions
├── outputs.tf                 # CloudFront URL, distribution ID
├── provider.tf                # AWS provider + us-east-1 alias for ACM
├── versions.tf                # Terraform and provider version constraints
├── terraform.tfvars.example   # Template — copy to terraform.tfvars
└── website/
└── index.html             # Static site content


---

## Deploy it yourself

```bash
# 1. Clone the repo
git clone https://github.com/tg-arun/tf-static-website.git
cd tf-static-website

# 2. Set your variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your domain name

# 3. Initialise Terraform (downloads AWS provider)
terraform init

# 4. Preview what will be created
terraform plan

# 5. Deploy (takes ~15 minutes — CloudFront deploys globally)
terraform apply
```

> **Note:** ACM certificate validation pauses Terraform for 2-5 minutes while AWS
> confirms domain ownership via DNS. CloudFront deployment takes another 10-15
> minutes to propagate to all edge locations. Both are normal.

---

## Cost

| Service | Cost |
|---|---|
| S3 storage | ~$0.00 (free tier) |
| CloudFront | Free tier: 1TB transfer + 10M requests/month |
| ACM certificate | Free |
| Route53 hosted zone | **$0.50/month** |

**Total: ~$0.50/month**

Run `terraform destroy` to tear down all resources and stop charges.

---

## Tear down

```bash
terraform destroy
```

This removes every resource Terraform created. Your Route53 hosted zone
is managed as a `data` source (not created by Terraform), so it will not
be deleted.

---

## Part of my Terraform learning series

This is Project 1 of a series building towards a production-grade AWS infrastructure portfolio:

| # | Project | Status |
|---|---|---|
| 1 | Static website — S3 + CloudFront + Route53 | ✅ Complete |
| 2 | Modules + remote state | 🔜 Coming soon |
| 3 | ECS + ALB + Auto Scaling | 🔜 Coming soon |
| 4 | CI/CD pipeline — GitHub Actions + Terraform | 🔜 Coming soon |
| 5 | Multi-environment platform with Terragrunt | 🔜 Coming soon |



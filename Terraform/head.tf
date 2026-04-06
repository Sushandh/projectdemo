provider "aws" {
  region = "us-east-1"
}

# ---------------- S3 BUCKET ----------------
resource "aws_s3_bucket" "website" {
  bucket = "my-simple-project-02" # 🔥 change this (must be unique)
}

resource "aws_s3_bucket_website_configuration" "config" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "public" {
  bucket = aws_s3_bucket.website.id

  block_public_acls   = false
  block_public_policy = false
  restrict_public_buckets = false
  ignore_public_acls  = false
}

resource "aws_s3_bucket_policy" "policy" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = "*",
      Action = ["s3:GetObject"],
      Resource = "${aws_s3_bucket.website.arn}/*"
    }]
  })
}

# ---------------- METRICS ----------------
resource "aws_s3_bucket_metric" "metrics" {
  bucket = aws_s3_bucket.website.bucket
  name   = "EntireBucket"
}

# ---------------- SNS (EMAIL ALERTS) ----------------
resource "aws_sns_topic" "alerts" {
  name = "s3-alerts-topic"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "ktsushandh978@gmail.com" # 🔥 change this
}

# ---------------- CLOUDWATCH ALARM ----------------
resource "aws_cloudwatch_metric_alarm" "s3_errors" {
  alarm_name          = "S3-4xx-Errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "4xxErrors"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Sum"
  threshold           = 5

  dimensions = {
    BucketName = aws_s3_bucket.website.bucket
    FilterId   = "EntireBucket"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ---------------- DASHBOARD ----------------
resource "aws_cloudwatch_dashboard" "dashboard" {
  dashboard_name = "S3-Dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric",
        x = 0,
        y = 0,
        width = 12,
        height = 6,
        properties = {
          metrics = [
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.website.bucket, "StorageType", "AllStorageTypes"]
          ],
          period = 300,
          stat = "Average",
          region = "us-east-1",
          title = "S3 Objects"
        }
      }
    ]
  })
}

# ---------------- OUTPUT ----------------
output "website_url" {
  value = aws_s3_bucket.website.website_endpoint
}
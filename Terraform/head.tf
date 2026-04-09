terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
    }
    archive = {
      source  = "hashicorp/archive"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ---------------- S3 WEBSITE ----------------
resource "aws_s3_bucket" "website" {
  bucket = "my-simple-project-001" # change this
}

resource "aws_s3_bucket_website_configuration" "config" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "public" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = false
  block_public_policy     = false
  restrict_public_buckets = false
  ignore_public_acls      = false
}

resource "aws_s3_bucket_policy" "policy" {
  bucket = aws_s3_bucket.website.id

  depends_on = [aws_s3_bucket_public_access_block.public]

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = "*",
      Action    = ["s3:GetObject"],
      Resource  = "${aws_s3_bucket.website.arn}/*"
    }]
  })
}

# ---------------- LOGS BUCKET ----------------
resource "aws_s3_bucket" "logs" {
  bucket = "my-simple-project-logs-001" # change this
}

resource "aws_s3_bucket_logging" "logging" {
  bucket = aws_s3_bucket.website.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "logs/"
}

# ---------------- SNS ----------------
resource "aws_sns_topic" "alerts" {
  name = "s3-alerts-topic"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "ktsushandh978@gmail.com" # change this
}

# ---------------- IAM ROLE ----------------
resource "aws_iam_role" "lambda_role" {
  name = "lambda-s3-sns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:GetObject"],
        Resource = "${aws_s3_bucket.logs.arn}/*"
      },
      {
        Effect = "Allow",
        Action = ["sns:Publish"],
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

# ---------------- LAMBDA CODE (INLINE FILE) ----------------
resource "local_file" "lambda_py" {
  filename = "${path.module}/lambda.py"

  content = <<EOF
import boto3
import os

sns = boto3.client('sns')
SNS_ARN = os.environ['SNS_ARN']

def lambda_handler(event, context):
    s3 = boto3.client('s3')

    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']

        obj = s3.get_object(Bucket=bucket, Key=key)
        data = obj['Body'].read().decode()

        for line in data.splitlines():
            parts = line.split()

            if len(parts) > 8:
                status = parts[8]

                if status == "200":
                    message = "You have opened the page"
                else:
                    message = "Page is not accessed"

                sns.publish(
                    TopicArn=SNS_ARN,
                    Message=message
                )
EOF
}

# ---------------- ZIP AUTOMATIC ----------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_py.filename
  output_path = "${path.module}/lambda.zip"
}

# ---------------- LAMBDA ----------------
resource "aws_lambda_function" "s3_monitor" {
  function_name = "s3-access-monitor"

  filename         = data.archive_file.lambda_zip.output_path
  handler          = "lambda.lambda_handler"
  runtime          = "python3.10"
  role             = aws_iam_role.lambda_role.arn
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_ARN = aws_sns_topic.alerts.arn
    }
  }
}

# ---------------- PERMISSION ----------------
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_monitor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.logs.arn
}

# ---------------- TRIGGER ----------------
resource "aws_s3_bucket_notification" "trigger" {
  bucket = aws_s3_bucket.logs.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_monitor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# ---------------- OUTPUT ----------------
output "website_url" {
  value = aws_s3_bucket_website_configuration.config.website_endpoint
}
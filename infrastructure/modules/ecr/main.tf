locals {
  repositories = var.repositories
}

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name = "${var.name_prefix}-${each.key}-${var.environment}"
  image_scanning_configuration {
    scan_on_push = true
  }
  image_tag_mutability = var.environment == "prod" ? "IMMUTABLE" : "MUTABLE"
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.standard_tags, {
    Name        = each.key
    Environment = var.environment
  })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.keep_tagged_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = [""]
          countType     = "imageCountMoreThan"
          countNumber   = var.keep_tagged_count
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images older than ${var.untagged_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_days
        }
        action = { type = "expire" }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "ecr_pull" {
  name        = "${var.name_prefix}-ecr-pull-${var.environment}"
  description = "Least-privilege ECR pull policy for ${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "PullFromRepositories"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = [for r in aws_ecr_repository.this : r.arn]
      }
    ]
  })

  tags = var.standard_tags
}

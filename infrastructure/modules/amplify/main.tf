# AWS Amplify module for static site hosting
# Supports deploying Next.js build output for renderer and client applications

resource "aws_amplify_app" "renderer" {
  name       = "${var.resource_prefix}-renderer"
  repository = var.renderer_repository_url

  # Access token for private repositories
  access_token = var.access_token != "" ? var.access_token : null

  # Build settings for Next.js
  build_spec = <<-EOT
    version: 1
    frontend:
      phases:
        preBuild:
          commands:
            - pnpm install --ignore-scripts
        build:
          commands:
            - pnpm build
      artifacts:
        baseDirectory: .next
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT

  # Environment variables
  environment_variables = var.renderer_env_vars

  # Enable auto branch creation
  enable_auto_branch_creation = var.enable_auto_branch_creation
  enable_branch_auto_build    = var.enable_branch_auto_build
  enable_branch_auto_deletion = var.enable_branch_auto_deletion

  # Platform
  platform = "WEB"

  tags = merge(
    var.standard_tags,
    {
      Name        = "${var.resource_prefix}-renderer"
      Application = "renderer"
    }
  )
}

resource "aws_amplify_app" "client" {
  name       = "${var.resource_prefix}-client"
  repository = var.client_repository_url

  # Access token for private repositories
  access_token = var.access_token != "" ? var.access_token : null

  # Build settings for Next.js
  build_spec = <<-EOT
    version: 1
    frontend:
      phases:
        preBuild:
          commands:
            - pnpm install --ignore-scripts
        build:
          commands:
            - pnpm build
      artifacts:
        baseDirectory: .next
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT

  # Environment variables
  environment_variables = var.client_env_vars

  # Enable auto branch creation
  enable_auto_branch_creation = var.enable_auto_branch_creation
  enable_branch_auto_build    = var.enable_branch_auto_build
  enable_branch_auto_deletion = var.enable_branch_auto_deletion

  # Platform
  platform = "WEB"

  tags = merge(
    var.standard_tags,
    {
      Name        = "${var.resource_prefix}-client"
      Application = "client"
    }
  )
}

# Main branch for renderer
resource "aws_amplify_branch" "renderer_main" {
  app_id      = aws_amplify_app.renderer.id
  branch_name = var.renderer_branch_name

  enable_auto_build = true

  framework = "Next.js - SSR"
  stage     = var.environment == "prod" ? "PRODUCTION" : "DEVELOPMENT"

  tags = merge(
    var.standard_tags,
    {
      Name        = "${var.resource_prefix}-renderer-${var.renderer_branch_name}"
      Application = "renderer"
      Branch      = var.renderer_branch_name
    }
  )
}

# Main branch for client
resource "aws_amplify_branch" "client_main" {
  app_id      = aws_amplify_app.client.id
  branch_name = var.client_branch_name

  enable_auto_build = true

  framework = "Next.js - SSR"
  stage     = var.environment == "prod" ? "PRODUCTION" : "DEVELOPMENT"

  tags = merge(
    var.standard_tags,
    {
      Name        = "${var.resource_prefix}-client-${var.client_branch_name}"
      Application = "client"
      Branch      = var.client_branch_name
    }
  )
}

# Custom domain for renderer (optional)
resource "aws_amplify_domain_association" "renderer" {
  count = var.renderer_custom_domain != "" ? 1 : 0

  app_id      = aws_amplify_app.renderer.id
  domain_name = var.renderer_custom_domain

  sub_domain {
    branch_name = aws_amplify_branch.renderer_main.branch_name
    prefix      = var.renderer_subdomain_prefix
  }

  wait_for_verification = false
}

# Custom domain for client (optional)
resource "aws_amplify_domain_association" "client" {
  count = var.client_custom_domain != "" ? 1 : 0

  app_id      = aws_amplify_app.client.id
  domain_name = var.client_custom_domain

  sub_domain {
    branch_name = aws_amplify_branch.client_main.branch_name
    prefix      = var.client_subdomain_prefix
  }

  wait_for_verification = false
}

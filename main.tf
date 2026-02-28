# PaymentForm Infrastructure
# 
# This directory contains the infrastructure configuration for PaymentForm.
# 
# ## Structure
# 
# - providers/     - Cloud provider modules (AWS, Cloudflare)
# - environments/  - Environment-specific configurations
# - modules/       - (Optional) Custom composed modules
# 
# ## Quick Start
# 
# ```bash
# # Navigate to your environment
# cd environments/sandbox
# 
# # Initialize and deploy
# tofu init && tofu plan -out=tfplan && tofu apply tfplan
# ```
# 
# ## Available Environments
# 
# - `dev/`      - Development environment
# - `sandbox/`  - Staging/testing environment
# - `prod/`     - Production environment
# 
# Each environment has its own state file and configuration.
# 
# See README.md for full documentation.

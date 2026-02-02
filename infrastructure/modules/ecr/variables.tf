variable "environment" {
  description = "Deployment environment (sandbox, prod)"
  type        = string
}

variable "repositories" {
  description = "List of repository/service names to create (e.g., [\"backend\", \"client\"])"
  type        = list(string)
  default     = ["backend", "client", "renderer", "admin"]
}

variable "keep_tagged_count" {
  description = "Number of tagged images to keep per repository"
  type        = number
  default     = 3
}

variable "untagged_days" {
  description = "Number of days after which untagged images are expired"
  type        = number
  default     = 1
}

variable "name_prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "standard_tags" {
  description = "Map of tags to apply to created resources"
  type        = map(string)
  default     = {}
}

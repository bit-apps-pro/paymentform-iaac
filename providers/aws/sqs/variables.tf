variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "name_suffix" {
  description = "Suffix appended to each AWS SQS queue resource name (e.g., '-paymentform-prod'). Laravel's SQS driver appends `SQS_SUFFIX` to every dispatched queue name, so the suffix MUST match `SQS_SUFFIX` in the consumer's env. Empty string is allowed for single-tenant accounts."
  type        = string
  default     = ""
  validation {
    condition     = var.name_suffix == "" || can(regex("^[-_a-zA-Z0-9]+$", var.name_suffix))
    error_message = "name_suffix may only contain letters, digits, hyphens and underscores."
  }
}

variable "queues" {
  description = "Logical queue names consumed by Laravel (e.g., 'default', 'webhooks'). Each gets one main queue and, if enable_dlq, one '-dlq' queue."
  type        = list(string)
  validation {
    condition     = length(var.queues) > 0
    error_message = "queues must contain at least one queue name."
  }
}

variable "enable_dlq" {
  description = "Create a dead-letter queue per main queue and bind via redrive_policy."
  type        = bool
  default     = true
}

variable "dlq_max_receive_count" {
  description = "Number of receives before a message is moved to the DLQ."
  type        = number
  default     = 3
}

variable "visibility_timeout_seconds" {
  description = "Default visibility timeout for any queue not listed in `queue_visibility_overrides`. Must exceed that queue's worker --timeout. 600 leaves headroom for the slowest worker (exports at 300s)."
  type        = number
  default     = 600
}

variable "queue_visibility_overrides" {
  description = "Per-queue visibility timeout (seconds). Lookup by logical queue name; queues not listed fall back to `visibility_timeout_seconds`. Use to tighten the redelivery window on short-running queues so a stuck job retries sooner. Each override MUST be >= that queue's worker --timeout, otherwise SQS re-delivers mid-execution and the job runs twice."
  type        = map(number)
  default     = {}
  validation {
    condition     = alltrue([for v in values(var.queue_visibility_overrides) : v >= 30 && v <= 43200])
    error_message = "Per-queue visibility timeouts must be between 30 and 43200 seconds (SQS hard limits)."
  }
}

variable "message_retention_seconds" {
  description = "Seconds a message is retained on the main queue (max 1209600 = 14 days)."
  type        = number
  default     = 345600 # 4 days
}

variable "dlq_message_retention_seconds" {
  description = "Seconds a message is retained on the DLQ (max 1209600 = 14 days)."
  type        = number
  default     = 1209600 # 14 days — keep failed jobs around for forensics
}

variable "receive_wait_time_seconds" {
  description = "Long-polling wait time on Receive. 20s is the AWS maximum and minimises API calls when queues are idle."
  type        = number
  default     = 20
}

variable "kms_master_key_id" {
  description = "Optional KMS key for server-side encryption. When null, SQS-managed SSE (sqs_managed_sse_enabled) is used instead."
  type        = string
  default     = null
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources."
  type        = map(string)
  default     = {}
}

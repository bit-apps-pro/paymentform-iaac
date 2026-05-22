terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  queue_set = toset(var.queues)
}

resource "aws_sqs_queue" "dlq" {
  for_each = var.enable_dlq ? local.queue_set : toset([])

  name                       = "${each.value}${var.name_suffix}-dlq"
  message_retention_seconds  = var.dlq_message_retention_seconds
  visibility_timeout_seconds = lookup(var.queue_visibility_overrides, each.value, var.visibility_timeout_seconds)
  receive_wait_time_seconds  = var.receive_wait_time_seconds

  kms_master_key_id                 = var.kms_master_key_id
  kms_data_key_reuse_period_seconds = var.kms_master_key_id != null ? 300 : null
  sqs_managed_sse_enabled           = var.kms_master_key_id == null

  tags = merge(
    var.standard_tags,
    {
      Name  = "${each.value}${var.name_suffix}-dlq"
      Queue = each.value
      Role  = "dlq"
    }
  )
}

resource "aws_sqs_queue" "main" {
  for_each = local.queue_set

  name                       = "${each.value}${var.name_suffix}"
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = lookup(var.queue_visibility_overrides, each.value, var.visibility_timeout_seconds)
  receive_wait_time_seconds  = var.receive_wait_time_seconds

  kms_master_key_id                 = var.kms_master_key_id
  kms_data_key_reuse_period_seconds = var.kms_master_key_id != null ? 300 : null
  sqs_managed_sse_enabled           = var.kms_master_key_id == null

  redrive_policy = var.enable_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.value].arn
    maxReceiveCount     = var.dlq_max_receive_count
  }) : null

  tags = merge(
    var.standard_tags,
    {
      Name  = "${each.value}${var.name_suffix}"
      Queue = each.value
      Role  = "main"
    }
  )
}

# Allow the DLQ to be the redrive target only for its paired main queue.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  for_each = var.enable_dlq ? local.queue_set : toset([])

  queue_url = aws_sqs_queue.dlq[each.value].id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main[each.value].arn]
  })
}

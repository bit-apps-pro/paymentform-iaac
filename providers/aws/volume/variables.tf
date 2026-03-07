variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "name" {
  description = "Name for the volume (e.g., postgresql-data)"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone for the volume"
  type        = string
}

variable "size" {
  description = "Size of the volume in GB"
  type        = number
}

variable "volume_type" {
  description = "EBS volume type (gp2, gp3, io1, io2, st1, sc1)"
  type        = string
  default     = "gp3"
}

variable "encrypted" {
  description = "Enable encryption at rest"
  type        = bool
  default     = true
}

variable "iops" {
  description = "IOPS for io1/io2/gp3 volumes"
  type        = number
  default     = null
}

variable "throughput" {
  description = "Throughput for gp3 volumes (MB/s)"
  type        = number
  default     = null
}

variable "device_name" {
  description = "Device name for attachment (e.g., /dev/sdf)"
  type        = string
  default     = "/dev/sdf"
}

variable "instance_id" {
  description = "Instance ID to attach the volume to"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "prevent_destroy" {
  description = "Prevent volume from being destroyed"
  type        = bool
  default     = true
}

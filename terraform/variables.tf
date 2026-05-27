variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t4g.small"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH (your IP, e.g. 1.2.3.4/32)"
  type        = string
}

variable "data_volume_size" {
  description = "Size in GB for the Hermes data EBS volume"
  type        = number
  default     = 50
}

variable "project_name" {
  description = "Name tag prefix for all resources"
  type        = string
  default     = "hermes"
}

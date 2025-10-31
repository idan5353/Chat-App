variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dr"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "devops-chat"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

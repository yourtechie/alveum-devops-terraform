variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "db_username" {
  description = "Username for the RDS database"
  default     = "admin"
}

variable "db_password" {
  description = "Password for the RDS database"
  sensitive   = true
}
variable "portainer_password" {
  description = "Portainer admin password"
  type        = string
  sensitive   = true
}

variable "endpoint_id" {
  description = "Portainer endpoint ID for dockermaster"
  type        = number
  default     = 3
}

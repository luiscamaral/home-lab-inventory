variable "portainer_endpoint" {
  description = "Portainer API endpoint URL"
  type        = string
  default     = "https://192.168.59.2:9443"
}

variable "portainer_password" {
  description = "Portainer admin password"
  type        = string
  sensitive   = true
}

variable "endpoint_id" {
  description = "Portainer endpoint ID for dockermaster (local, ID=3)"
  type        = number
  default     = 3
}

variable "ds1_endpoint_id" {
  description = "Portainer endpoint ID for dockerserver-1 (agent, ID=9)"
  type        = number
  default     = 9
}

variable "ds2_endpoint_id" {
  description = "Portainer endpoint ID for dockerserver-2 (agent, ID=13)"
  type        = number
  default     = 13
}


variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = "http://vault.d.lcamaral.com"
}

variable "vault_token" {
  description = "Vault authentication token"
  type        = string
  sensitive   = true
}

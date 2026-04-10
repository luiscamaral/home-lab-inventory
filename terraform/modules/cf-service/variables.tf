variable "name" {
  description = "Service name (becomes <name>.cf.lcamaral.com)"
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID"
  type        = string
}

variable "tunnel_id" {
  description = "Cloudflare tunnel ID"
  type        = string
}

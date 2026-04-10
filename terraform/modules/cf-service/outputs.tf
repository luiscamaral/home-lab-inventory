output "fqdn" {
  description = "Fully qualified domain name of the service"
  value       = "${var.name}.cf.lcamaral.com"
}

output "dns_record_id" {
  description = "Cloudflare DNS record ID"
  value       = cloudflare_dns_record.service.id
}

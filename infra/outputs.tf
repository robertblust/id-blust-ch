output "dns_records" {
  description = "What the domain needs; create these at Hostpoint, where blust.ch's records are kept"
  value = [
    { name = local.d.domain, type = "A", data = google_compute_global_address.id.address },
  ]
}

output "issuer" {
  description = "ZITADEL's issuer, which the post-apply check reads from its discovery document"
  value       = local.issuer
}

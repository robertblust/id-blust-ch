# id.blust.ch reaches the two services through a global external Application Load Balancer with a
# Google-managed certificate, and not through a Cloud Run domain mapping, for two reasons that
# each decide it alone. Domain mappings are not offered in europe-west6: Cloud Run's documentation
# lists asia-east1, asia-northeast1, asia-southeast1, europe-north1, europe-west1, europe-west4,
# us-central1, us-east1, us-east4 and us-west1, and says a domain maps to / only, never to a
# path (https://docs.cloud.google.com/run/docs/mapping-custom-domains, read Oct 22, 2026). And
# login v2 is a separate deployment that must be reachable under /ui/v2/login of ZITADEL's own
# domain, with that path and its subpaths routed to the login and everything else to the API
# (https://zitadel.com/docs/self-hosting/manage/adopt-login-v2, read Oct 22, 2026); ZITADEL v4
# still serves its built-in login from the one service, but that is login v1, which this instance
# leaves once its token exists. So the services stay in Zurich, behind the load balancer, which
# the owner prefers to another region. Google-managed certificates work on the global load
# balancer only. The load balancer speaks HTTP/2 to ZITADEL, which needs it for its gRPC API.
resource "google_compute_global_address" "id" {
  name = "id"
}

resource "google_compute_managed_ssl_certificate" "id" {
  name = "id"
  managed {
    domains = [local.d.domain]
  }
}

locals {
  run_services = {
    zitadel = google_cloud_run_v2_service.zitadel.name
    login   = google_cloud_run_v2_service.login.name
  }
}

resource "google_compute_region_network_endpoint_group" "run" {
  for_each              = local.run_services
  name                  = each.value
  region                = local.d.region
  network_endpoint_type = "SERVERLESS"
  cloud_run {
    service = each.value
  }
}

resource "google_compute_backend_service" "run" {
  for_each              = local.run_services
  name                  = each.value
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = each.key == "zitadel" ? "HTTP2" : "HTTPS"
  backend {
    group = google_compute_region_network_endpoint_group.run[each.key].id
  }
}

# One host, two paths: the login under /ui/v2/login, everything else to ZITADEL. A request for
# any other host reaches ZITADEL too, which answers it with its own error for an unknown domain.
resource "google_compute_url_map" "id" {
  name            = "id"
  default_service = google_compute_backend_service.run["zitadel"].id

  host_rule {
    hosts        = [local.d.domain]
    path_matcher = "id"
  }
  path_matcher {
    name            = "id"
    default_service = google_compute_backend_service.run["zitadel"].id
    path_rule {
      paths   = ["/ui/v2/login", "/ui/v2/login/*"]
      service = google_compute_backend_service.run["login"].id
    }
  }
}

resource "google_compute_target_https_proxy" "id" {
  name             = "id"
  url_map          = google_compute_url_map.id.id
  ssl_certificates = [google_compute_managed_ssl_certificate.id.id]
}

resource "google_compute_global_forwarding_rule" "id" {
  name                  = "id"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.id.id
  port_range            = "443"
  target                = google_compute_target_https_proxy.id.id
}

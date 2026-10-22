# What this root runs, planned against mocked providers: both services scale to zero, the front
# routes the login's path to the login and speaks HTTP/2 to ZITADEL, plain HTTP only redirects,
# no generated secret is a plain argument, and a missing login name is refused.
# The random provider runs for real: it makes the ephemeral passwords locally and calls nothing,
# and a mock provider cannot stand in for an ephemeral resource.
mock_provider "google" {}

variables {
  admin_login_name = "owner@example.com"
}

run "plan" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.zitadel.template[0].scaling[0].min_instance_count == 0 && google_cloud_run_v2_service.login.template[0].scaling[0].min_instance_count == 0
    error_message = "Both services scale to zero."
  }
  assert {
    condition     = join(",", sort(tolist(google_compute_url_map.id.path_matcher[0].path_rule[0].paths))) == "/ui/v2/login,/ui/v2/login/*"
    error_message = "The login's path goes to the login."
  }
  assert {
    condition     = google_compute_backend_service.run["zitadel"].protocol == "HTTP2"
    error_message = "The load balancer speaks HTTP/2 to ZITADEL."
  }
  assert {
    condition     = google_compute_url_map.redirect.default_url_redirect[0].https_redirect == true && google_compute_global_forwarding_rule.redirect.port_range == "80"
    error_message = "Port 80 only redirects to HTTPS."
  }
  assert {
    condition     = google_compute_ssl_policy.id.min_tls_version == "TLS_1_2"
    error_message = "TLS 1.2 is the floor."
  }
  assert {
    condition     = length(google_secret_manager_secret.s) == 6 && alltrue([for v in google_secret_manager_secret_version.generated : v.secret_data == null])
    error_message = "Six secrets, and no generated value is a plain argument."
  }
  assert {
    condition     = google_sql_user.zitadel.password == null
    error_message = "The database password is write-only."
  }
}

run "no_login_name" {
  command = plan

  variables {
    admin_login_name = ""
  }

  expect_failures = [var.admin_login_name]
}

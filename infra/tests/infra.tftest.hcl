# What this root runs, planned against mocked providers: both services scale to zero, the front
# routes the login's path to the login and speaks HTTP/2 to ZITADEL, plain HTTP only redirects,
# no generated secret is a plain argument, and a missing login name is refused. And the names the
# bootstrap's conditions hold CI's identities to in the project shared with the MCP host: every
# secret is zitadel-*, the instance is zitadel, and the services run as the bootstrap's accounts.
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
    condition     = length(google_secret_manager_secret.s) == 7 && alltrue([for v in google_secret_manager_secret_version.generated : v.secret_data == null]) && google_secret_manager_secret_version.db_password.secret_data == null
    error_message = "Seven secrets, and no generated value is a plain argument."
  }
  assert {
    condition     = google_sql_user.zitadel.password == null
    error_message = "The database password is write-only."
  }
  assert {
    condition     = alltrue([for id in keys(google_secret_manager_secret.s) : startswith(id, "zitadel-")])
    error_message = "Every secret is named zitadel-*, the only secrets the bootstrap lets CI administer in the shared project."
  }
  assert {
    condition     = google_sql_database_instance.zitadel.name == "zitadel"
    error_message = "The instance is zitadel, the only one the bootstrap lets CI administer in the shared project."
  }
  assert {
    condition     = google_cloud_run_v2_service.zitadel.template[0].service_account == "zitadel@blust-ch-mcp.iam.gserviceaccount.com" && google_cloud_run_v2_service.login.template[0].service_account == "zitadel-login@blust-ch-mcp.iam.gserviceaccount.com"
    error_message = "The services run as the two accounts the bootstrap made, the only ones CI may act as."
  }
  assert {
    condition     = google_project_iam_member.zitadel_sql.condition[0].expression == "resource.type != \"sqladmin.googleapis.com/Instance\" || resource.name == \"projects/blust-ch-mcp/instances/zitadel\""
    error_message = "ZITADEL's Cloud SQL client role reaches its own instance only."
  }
  assert {
    condition     = google_secret_manager_secret_iam_member.reader["zitadel-admin-key/deploy"].member == "serviceAccount:id-deploy@blust-ch-mcp.iam.gserviceaccount.com" && google_secret_manager_secret_iam_member.reader["zitadel-admin-key/deploy-plan"].member == "serviceAccount:id-deploy-plan@blust-ch-mcp.iam.gserviceaccount.com"
    error_message = "The admin key is read by this repository's identities, not by the MCP host's deploy@."
  }
  assert {
    condition     = join(",", sort([for k, r in google_secret_manager_secret_iam_member.reader : r.member if startswith(k, "zitadel-google-client-secret/")])) == "serviceAccount:id-deploy-plan@blust-ch-mcp.iam.gserviceaccount.com,serviceAccount:id-deploy@blust-ch-mcp.iam.gserviceaccount.com"
    error_message = "The Google client secret is read by the two identities that plan and apply ../zitadel, and by nobody else."
  }
  assert {
    condition     = contains(keys(google_secret_manager_secret.s), "zitadel-google-client-secret") && !contains(keys(google_secret_manager_secret_version.generated), "zitadel-google-client-secret")
    error_message = "The Google client secret exists and starts empty; its value is the owner's."
  }
}

run "no_login_name" {
  command = plan

  variables {
    admin_login_name = ""
  }

  expect_failures = [var.admin_login_name]
}

# ZITADEL and its login, two Cloud Run services that both scale to zero: nobody signs in most of
# the hour, and the first sign-in after a quiet spell waits a few seconds for them to start, which
# the owner accepts. Both are reached only through the load balancer in domain.tf, as their
# ingress says, and the invoker check is off rather than open to allUsers. The project does
# allow allUsers, through the override of the organization's domain-restricted sharing that the
# MCP host's bootstrap sets for its public services, but that override is mcp-blust-ch's to keep
# or drop, and with the check off these services need no grant that depends on it.
locals {
  sql = google_sql_database_instance.zitadel.connection_name
  # ZITADEL reads every setting from a ZITADEL_ variable named after its path in defaults.yaml
  # and steps.yaml.
  zitadel_env = {
    ZITADEL_EXTERNALDOMAIN = local.d.domain
    ZITADEL_EXTERNALPORT   = "443"
    ZITADEL_EXTERNALSECURE = "true"

    ZITADEL_DATABASE_POSTGRES_HOST           = "/cloudsql/${local.sql}"
    ZITADEL_DATABASE_POSTGRES_DATABASE       = google_sql_database.zitadel.name
    ZITADEL_DATABASE_POSTGRES_USER_USERNAME  = google_sql_user.zitadel.name
    ZITADEL_DATABASE_POSTGRES_USER_SSL_MODE  = "disable"
    ZITADEL_DATABASE_POSTGRES_ADMIN_USERNAME = google_sql_user.zitadel.name
    ZITADEL_DATABASE_POSTGRES_ADMIN_SSL_MODE = "disable"
    # db-f1-micro allows 25 connections, about three of them kept for Cloud SQL itself, so about
    # 22 are ZITADEL's, and ZITADEL opens up to ten by default. Seven each, two kept idle, fits
    # three instances in 21: the two the service may scale to, and one more while a new revision
    # starts beside the old.
    ZITADEL_DATABASE_POSTGRES_MAXOPENCONNS = "7"
    ZITADEL_DATABASE_POSTGRES_MAXIDLECONNS = "2"

    # The first start makes the instance, its first organization and that organization's first
    # human admin, the owner, whose login name is their email address; ZITADEL then uses it as
    # the address too. Nothing here counts on a later start.
    ZITADEL_FIRSTINSTANCE_INSTANCENAME       = local.d.domain
    ZITADEL_FIRSTINSTANCE_ORG_NAME           = "blust.ch"
    ZITADEL_FIRSTINSTANCE_ORG_HUMAN_USERNAME = var.admin_login_name

    # The instance starts on the built-in login, which ZITADEL still serves from this service,
    # because login v2 cannot sign anyone in before the owner has made its token, and the owner
    # needs a sign-in to make it. ../zitadel turns login v2 on once the token is in place.
    ZITADEL_DEFAULTINSTANCE_FEATURES_LOGINV2_REQUIRED = "false"
  }
  zitadel_secrets = {
    ZITADEL_MASTERKEY                        = "zitadel-masterkey"
    ZITADEL_DATABASE_POSTGRES_USER_PASSWORD  = "zitadel-db-password"
    ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD = "zitadel-db-password"
    ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD = "zitadel-admin-password"
  }
}

# ZITADEL speaks HTTP/2 without TLS, so the port is named h2c and the load balancer talks HTTP/2
# to it; TLS ends at the load balancer, hence --tlsMode external with the external domain on 443.
# start-from-init runs the database's setup on every start, which does nothing once it is done.
resource "google_cloud_run_v2_service" "zitadel" {
  name                 = "zitadel"
  location             = local.d.region
  ingress              = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  invoker_iam_disabled = true
  deletion_protection  = false

  template {
    service_account = local.zitadel_email
    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [local.sql]
      }
    }
    containers {
      image = "ghcr.io/zitadel/zitadel:${var.zitadel_version}"
      args  = ["start-from-init", "--masterkeyFromEnv", "--tlsMode", "external"]
      ports {
        name           = "h2c"
        container_port = 8080
      }
      resources {
        limits = { cpu = "1", memory = "1Gi" }
        # More CPU while an instance starts, so the first sign-in after a quiet spell waits less.
        startup_cpu_boost = true
      }
      dynamic "env" {
        for_each = local.zitadel_env
        content {
          name  = env.key
          value = env.value
        }
      }
      dynamic "env" {
        for_each = local.zitadel_secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.s[env.value].secret_id
              version = "latest"
            }
          }
        }
      }
      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
    }
  }
  depends_on = [
    google_secret_manager_secret_iam_member.reader,
    google_secret_manager_secret_version.generated,
    google_secret_manager_secret_version.db_password,
    google_project_iam_member.zitadel_sql,
    google_sql_user.zitadel,
    google_sql_database.zitadel,
  ]
}

# The login v2, a Next.js application of its own, served under /ui/v2/login of the same domain.
# It calls ZITADEL's API at the public address, through the same load balancer, so the API sees
# the instance's own domain without a header rewritten.
#
# Its image is ZITADEL's login at the same release, with the one row ../login/Dockerfile changes,
# which infra.yml builds and pushes to the GitHub Container Registry before this root applies.
# The tag names the release and the Dockerfile's hash, so a change to either deploys a new
# revision, and a tag once pushed always means the same build.
locals {
  login_image = "ghcr.io/robertblust/id-blust-ch-login:${var.zitadel_version}-${substr(filesha256("${path.module}/../login/Dockerfile"), 0, 12)}"
}

resource "google_cloud_run_v2_service" "login" {
  name                 = "zitadel-login"
  location             = local.d.region
  ingress              = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  invoker_iam_disabled = true
  deletion_protection  = false

  template {
    service_account = local.login_email
    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }
    containers {
      image = local.login_image
      ports {
        container_port = 3000
      }
      resources {
        limits            = { cpu = "1", memory = "512Mi" }
        startup_cpu_boost = true
      }
      env {
        name  = "ZITADEL_API_URL"
        value = local.issuer
      }
      env {
        name  = "NEXT_PUBLIC_BASE_PATH"
        value = "/ui/v2/login"
      }
      env {
        name = "ZITADEL_SERVICE_USER_TOKEN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.s["zitadel-login-token"].secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "ZITADEL_SESSION_COOKIE_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.s["zitadel-login-cookie-secret"].secret_id
            version = "latest"
          }
        }
      }
    }
  }
  depends_on = [
    google_secret_manager_secret_iam_member.reader,
    google_secret_manager_secret_version.generated,
    google_secret_manager_secret_version.login_token_placeholder,
  ]
}

# PostgreSQL for ZITADEL, the one part that runs all month: Enterprise edition is set explicitly,
# because only it has the shared-core tiers, and the smallest of them carries no SLA, which an
# identity service for three sites' chats accepts. ZITADEL reaches it through the Cloud SQL
# socket Cloud Run mounts, so the instance has a public address with no authorized network: only
# the connector, which signs in with the service's identity and encrypts, can use it.
resource "google_sql_database_instance" "zitadel" {
  name                = "zitadel"
  database_version    = "POSTGRES_18"
  region              = local.d.region
  deletion_protection = true

  settings {
    edition           = "ENTERPRISE"
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_size         = 10
    ip_configuration {
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY"
    }
    backup_configuration {
      enabled = true
    }
  }
}

resource "google_sql_database" "zitadel" {
  name     = "zitadel"
  instance = google_sql_database_instance.zitadel.name
}

# A user made through Cloud SQL's API belongs to cloudsqlsuperuser, which may create the schema,
# so ZITADEL's first start uses it as its admin connection as well and needs no second password.
resource "google_sql_user" "zitadel" {
  name     = "zitadel"
  instance = google_sql_database_instance.zitadel.name
  password = random_password.db.result
}

# What runs ZITADEL at id.blust.ch, applied by CI on every push to main: the database, the
# secrets, the two Cloud Run services and the load balancer in front of them. State lives in the
# bucket the bootstrap made, and this deployment's own values come from deployment.json. What
# ZITADEL holds, its organizations, project, roles and applications, is the second root,
# ../zitadel, applied after this one.
terraform {
  required_version = ">= 1.10"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 8.0" }
    random = { source = "hashicorp/random", version = "~> 3.7" }
  }
  backend "gcs" {
    bucket = "id-blust-ch-tfstate"
    prefix = "infra"
  }
}

locals {
  d      = jsondecode(file("${path.module}/../deployment.json"))
  issuer = "https://${local.d.domain}"
}

provider "google" {
  project = local.d.project
  region  = local.d.region
}

# One identity per service, so each reads only the secrets it uses: ZITADEL the masterkey, the
# database password and the first admin's password, the login its token and its cookie secret.
resource "google_service_account" "zitadel" {
  account_id   = "zitadel"
  display_name = "ZITADEL on Cloud Run"
}

resource "google_service_account" "login" {
  account_id   = "zitadel-login"
  display_name = "ZITADEL's login on Cloud Run"
}

resource "google_project_iam_member" "zitadel_sql" {
  project = local.d.project
  role    = "roles/cloudsql.client"
  member  = google_service_account.zitadel.member
}

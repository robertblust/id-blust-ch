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
# The bootstrap makes both accounts, since making one here would take roles that, in a project
# shared with the MCP host, reach every account the project has; this root only names them.
locals {
  zitadel_email  = "zitadel@${local.d.project}.iam.gserviceaccount.com"
  login_email    = "zitadel-login@${local.d.project}.iam.gserviceaccount.com"
  zitadel_member = "serviceAccount:${local.zitadel_email}"
  login_member   = "serviceAccount:${local.login_email}"
}

# The Cloud SQL client on ZITADEL's instance alone, which a condition on the instance's name
# holds it to, as the bootstrap's conditions hold CI's identities; on the project it would reach
# any instance the project ever holds. It is the one project grant this root makes, and the only
# role the bootstrap lets id-deploy@ grant.
resource "google_project_iam_member" "zitadel_sql" {
  project = local.d.project
  role    = "roles/cloudsql.client"
  member  = local.zitadel_member
  condition {
    title       = "ZITADEL's instance only"
    description = "The Cloud SQL instance this root makes, and no other."
    expression  = "resource.type != \"sqladmin.googleapis.com/Instance\" || resource.name == \"projects/${local.d.project}/instances/${google_sql_database_instance.zitadel.name}\""
  }
}

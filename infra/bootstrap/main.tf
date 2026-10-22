# What has to exist before GitHub Actions can authenticate: applied by the owner under their own
# login, with local state, and changed only when the repository or the CI identities change.
# Everything below the project that CI can create lives in ../ and ../../zitadel and is applied
# by CI. This deployment's own values come from deployment.json.
terraform {
  required_version = ">= 1.10"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 8.0" }
  }
}

locals {
  d = jsondecode(file("${path.module}/../../deployment.json"))
  # The flatland.ch organization, which holds the family's other projects too.
  organization = "14986580178"
}

provider "google" {
  project = local.d.project
  region  = local.d.region
}

# The Budget API bills its calls to a quota project, and a user's local credentials name none, so
# the budget alone is written through a provider that names this project. It cannot be the
# default provider: the project does not exist when the first apply creates it, and a quota
# project that does not exist refuses every call made in its name.
provider "google" {
  alias                 = "billing"
  project               = local.d.project
  region                = local.d.region
  user_project_override = true
  billing_project       = local.d.project
}

resource "google_project" "this" {
  project_id      = local.d.project
  name            = local.d.project
  org_id          = local.organization
  billing_account = local.d.billing_account
  deletion_policy = "PREVENT"
}

# Enabling an API already on is a no-op; disabling one on destroy never happens. Storage and
# Service Usage are on in a new project already and are named so that nothing depends on that.
resource "google_project_service" "bootstrap" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "billingbudgets.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
  ])
  project                    = google_project.this.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_storage_bucket" "state" {
  name                        = "${local.d.project}-tfstate"
  project                     = google_project.this.project_id
  location                    = local.d.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  versioning { enabled = true }
  lifecycle_rule {
    condition { num_newer_versions = 10 }
    action { type = "Delete" }
  }
  depends_on = [google_project_service.bootstrap]
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = google_project.this.project_id
  workload_identity_pool_id = "github"
  depends_on                = [google_project_service.bootstrap]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = google_project.this.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  attribute_mapping = {
    "google.subject"          = "assertion.sub"
    "attribute.repository"    = "assertion.repository"
    "attribute.repository_id" = "assertion.repository_id"
    "attribute.ref"           = "assertion.ref"
    "attribute.event_name"    = "assertion.event_name"
  }
  # The id, not the name: a repository deleted or renamed frees its name for anyone, and a
  # condition on the name would hand this project to whoever takes it.
  attribute_condition = "assertion.repository_id == \"${local.d.repository_id}\""
  oidc { issuer_uri = "https://token.actions.githubusercontent.com" }
  lifecycle {
    precondition {
      condition     = can(regex("^[0-9]+$", local.d.repository_id))
      error_message = "deployment.json's repository_id is GitHub's numeric id for the repository: gh api repos/robertblust/id-blust-ch --jq .id"
    }
  }
}

# Only this repository's tokens pass the provider, so a principal set over one attribute is
# already that repository's. A run for a pull request may plan, and only a run on main may change
# anything, which keeps a pull request, Dependabot's included, from applying. A pull request's
# ref is refs/pull/<n>/merge, never main, so no run is both.
locals {
  pool          = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}"
  pull_requests = "${local.pool}/attribute.event_name/pull_request"
  main_runs     = "${local.pool}/attribute.ref/refs/heads/main"
}

# Applies ../ and ../../zitadel on a push to main: the services, the database, the secrets and
# the load balancer, and the IAM that ties them together. Each role is the narrowest that makes
# one kind of resource there. The service account user lets it run the services as their
# identities. The project IAM administrator is held to the one project grant ../ makes, the
# Cloud SQL client role for ZITADEL's identity, so this account cannot grant itself or anyone
# else another role on the project.
#
# Secrets it administers through the role below, which leaves out reading a value: it makes the
# secrets, writes the generated values and sets who reads each. The one value it reads is
# zitadel-admin-key, for the zitadel root's provider, by a grant on that secret alone in
# ../secrets.tf. Setting a secret's policy is setting who reads it, so this account could grant
# itself any other secret too; what keeps it from doing so unseen is that every grant is in
# ../secrets.tf and in the audit log.
resource "google_project_iam_custom_role" "secrets" {
  project     = google_project.this.project_id
  role_id     = "secretsWithoutAccess"
  title       = "Secret Manager administrator without access to values"
  description = "Makes secrets, adds and manages their versions and sets their IAM policies, and never reads a value."
  permissions = [
    "secretmanager.secrets.create",
    "secretmanager.secrets.delete",
    "secretmanager.secrets.get",
    "secretmanager.secrets.list",
    "secretmanager.secrets.update",
    "secretmanager.secrets.getIamPolicy",
    "secretmanager.secrets.setIamPolicy",
    "secretmanager.versions.add",
    "secretmanager.versions.destroy",
    "secretmanager.versions.disable",
    "secretmanager.versions.enable",
    "secretmanager.versions.get",
    "secretmanager.versions.list",
  ]
  depends_on = [google_project_service.bootstrap]
}
resource "google_service_account" "deploy" {
  project      = google_project.this.project_id
  account_id   = "deploy"
  display_name = "Terraform apply, run by GitHub Actions on main"
  depends_on   = [google_project_service.bootstrap]
}

resource "google_project_iam_member" "deploy" {
  for_each = toset([
    "roles/run.admin",
    "roles/cloudsql.admin",
    "roles/compute.loadBalancerAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/serviceusage.serviceUsageConsumer",
  ])
  project = google_project.this.project_id
  role    = each.value
  member  = google_service_account.deploy.member
}

resource "google_project_iam_member" "deploy_secrets" {
  project = google_project.this.project_id
  role    = google_project_iam_custom_role.secrets.name
  member  = google_service_account.deploy.member
}

resource "google_project_iam_member" "deploy_iam" {
  project = google_project.this.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = google_service_account.deploy.member
  condition {
    title       = "Grants only the Cloud SQL client role"
    description = "The one project grant ../ makes, to ZITADEL's identity."
    expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(['roles/cloudsql.client'])"
  }
}

resource "google_storage_bucket_iam_member" "deploy_state" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.deploy.member
}

resource "google_service_account_iam_member" "deploy_wif" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.main_runs
}

# Plans a pull request: reads the configuration of everything ../ and ../../zitadel declare and
# the state they keep, and can change none of it; -lock=false in the plan is what lets it do
# without write on the bucket. The state holds no secret, since every generated value is
# ephemeral and written write-only. It reads no secret's value but one: zitadel-admin-key, granted
# on that secret alone in ../secrets.tf, because the zitadel root's plan has to sign in to ZITADEL
# to read what it holds, and that key is the instance's IAM_OWNER. So a pull request run holds
# that key while it runs, and nothing on the Google side beyond reading.
resource "google_service_account" "plan" {
  project      = google_project.this.project_id
  account_id   = "deploy-plan"
  display_name = "Terraform plan, run by GitHub Actions on a pull request"
  depends_on   = [google_project_service.bootstrap]
}

resource "google_project_iam_member" "plan" {
  for_each = toset([
    "roles/viewer",
    "roles/cloudsql.viewer",
    "roles/iam.securityReviewer",
    "roles/serviceusage.serviceUsageConsumer",
  ])
  project = google_project.this.project_id
  role    = each.value
  member  = google_service_account.plan.member
}

resource "google_storage_bucket_iam_member" "plan_state" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.plan.member
}

resource "google_service_account_iam_member" "plan_wif" {
  service_account_id = google_service_account.plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.pull_requests
}

# A monthly budget of budget_chf francs, three warnings, to whoever administers the billing
# account. It lives here and not in ../ because only a billing administrator can write it, and
# the owner is one where CI's identities are not and must not be.
resource "google_billing_budget" "monthly" {
  provider        = google.billing
  billing_account = local.d.billing_account
  display_name    = "${local.d.domain} monthly"
  budget_filter {
    projects = ["projects/${google_project.this.number}"]
  }
  amount {
    specified_amount {
      currency_code = "CHF"
      units         = tostring(local.d.budget_chf)
    }
  }
  threshold_rules { threshold_percent = 0.5 }
  threshold_rules { threshold_percent = 0.9 }
  threshold_rules { threshold_percent = 1.0 }
  depends_on = [google_project_service.bootstrap]
  lifecycle {
    precondition {
      condition     = can(regex("^[0-9]+$", tostring(local.d.budget_chf)))
      error_message = "deployment.json's budget_chf is the owner's monthly figure in whole francs."
    }
  }
}

output "project_number" { value = google_project.this.number }
output "workload_identity_provider" { value = google_iam_workload_identity_pool_provider.github.name }
output "deploy_service_account" { value = google_service_account.deploy.email }
output "plan_service_account" { value = google_service_account.plan.email }
output "state_bucket" { value = google_storage_bucket.state.name }

# What has to exist before GitHub Actions can authenticate: applied by the owner under their own
# login, with local state, and changed only when the repository or the CI identities change.
# Everything CI can create lives in ../ and ../../zitadel and is applied by CI. This deployment's
# own values come from deployment.json.
#
# ZITADEL belongs to blust.ch, so it runs in blust.ch's project, blust-ch-mcp, beside the MCP
# host and its chat, which robertblust/mcp-blust-ch deploys from the shared bootstrap in
# companygraph/mcp-server's deploy/google/bootstrap and its own roots infra/ and infra/chat. This
# root makes no project, no budget and no organization policy: the project, its billing, its one
# budget and its override of the organization's domain-restricted sharing are mcp-blust-ch's. What
# it makes sits beside what mcp-blust-ch makes, so every name below was checked against that
# repository's: where the two would meet, the name here carries id-, and its comment says so.
terraform {
  required_version = ">= 1.10"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 8.0" }
  }
}

locals {
  d = jsondecode(file("${path.module}/../../deployment.json"))

  # The two names every resource condition below holds an identity to. Secret Manager names a
  # secret in a condition by the project's number and Cloud SQL an instance by the project's id,
  # and neither accepts the other. ../ names every secret zitadel-* and the instance zitadel, and
  # its test holds it to both, since a secret or an instance named otherwise would fall outside
  # what CI may touch. Nothing of the MCP host's has either name.
  secrets      = "projects/${local.d.project_number}/secrets/zitadel-"
  sql_instance = "projects/${local.d.project}/instances/zitadel"

  # A resource condition on a project grant sees the resource each permission is checked on.
  # Creating and listing are checked on the project, which carries no name a condition can read,
  # so each condition lets every other resource type through and holds the name only for the
  # types that carry one; the roles it sits on hold no permission on anything else
  # (https://docs.cloud.google.com/iam/docs/configuring-resource-based-access, read Oct 23, 2026).
  zitadel_secrets = join(" || ", [
    "(resource.type != \"secretmanager.googleapis.com/Secret\" && resource.type != \"secretmanager.googleapis.com/SecretVersion\")",
    "resource.name.startsWith(\"${local.secrets}\")",
  ])
  zitadel_sql = join(" || ", [
    "(resource.type != \"sqladmin.googleapis.com/Instance\" && resource.type != \"sqladmin.googleapis.com/BackupRun\")",
    "resource.name == \"${local.sql_instance}\"",
    "resource.name.startsWith(\"${local.sql_instance}/\")",
  ])
}

# Some of these APIs bill their calls to a quota project, and a user's local credentials name
# none, so the provider names the project, as mcp-blust-ch's bootstrap does.
provider "google" {
  project               = local.d.project
  region                = local.d.region
  user_project_override = true
  billing_project       = local.d.project
}

# Every API the roots of this repository use. Most are on already, enabled by mcp-blust-ch's
# bootstrap or its roots; they are named here too, so that ZITADEL depends on none of that
# repository's choices, and since enabling an API already on is a no-op and every one of them
# carries disable_on_destroy = false on both sides, destroying either root never turns off an API
# the other uses. Cloud SQL and Compute Engine are ZITADEL's alone.
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
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
  ])
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Named for the repository and not for the project: the project's name would give
# blust-ch-mcp-tfstate, which is the bucket mcp-blust-ch keeps its own state in.
resource "google_storage_bucket" "state" {
  name                        = "id-blust-ch-tfstate"
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

# id-github, because the MCP host's pool in the same project is github. A pool of its own keeps
# the two repositories apart: this one's provider accepts only this repository's tokens, and no
# identity of the MCP host's names this pool. The provider's id is scoped to its pool, so it
# stays github.
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "id-github"
  depends_on                = [google_project_service.bootstrap]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  attribute_mapping = {
    "google.subject"          = "assertion.sub"
    "attribute.repository"    = "assertion.repository"
    "attribute.repository_id" = "assertion.repository_id"
    "attribute.ref"           = "assertion.ref"
    "attribute.event_name"    = "assertion.event_name"
    "attribute.event_ref"     = "assertion.event_name + ':' + assertion.ref"
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
    precondition {
      condition     = can(regex("^[0-9]+$", local.d.project_number))
      error_message = "deployment.json's project_number is the project's number, which the workflows and the secret condition are built from: gcloud projects describe blust-ch-mcp --format='value(projectNumber)'"
    }
  }
}

# Only this repository's tokens pass the provider, so a principal set over one attribute is
# already that repository's. A run for a pull request may plan, and only a push to main may
# change anything: the apply binding names the event and the ref together, so a run on main
# started any other way, by hand, on a schedule, by a comment or as pull_request_target, gets
# neither identity, and a pull request, Dependabot's included, never applies.
locals {
  pool          = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}"
  pull_requests = "${local.pool}/attribute.event_name/pull_request"
  main_pushes   = "${local.pool}/attribute.event_ref/push:refs/heads/main"
}

# The identities ZITADEL and its login run as. They are made here rather than in ../ because the
# project is shared: making a service account in ../ would need the service account
# administrator, and running a service as it the service account user, both on the project, and
# on the project they reach every account the MCP host has, terraform@ among them, which holds
# the project IAM administrator without a condition. Made here, CI may act as these two and no
# other. Neither name is one the MCP host uses.
resource "google_service_account" "zitadel" {
  account_id   = "zitadel"
  display_name = "ZITADEL on Cloud Run"
  depends_on   = [google_project_service.bootstrap]
}

resource "google_service_account" "login" {
  account_id   = "zitadel-login"
  display_name = "ZITADEL's login on Cloud Run"
  depends_on   = [google_project_service.bootstrap]
}

# Applies ../ and ../../zitadel on a push to main: the services, the database, the secrets and
# the load balancer, and the IAM that ties them together. id-deploy, because the MCP host's
# bootstrap already has a deploy@ in this project, its image pusher.
#
# Each role is the narrowest that makes one kind of resource there, and in a shared project each
# reaches the MCP host's resources of that kind too, unless a condition holds it to ZITADEL's.
# Secret Manager and Cloud SQL accept a condition on the resource's name, so the secrets role is
# held to secrets named zitadel-* and the Cloud SQL administrator to the instance zitadel.
# Cloud Run and Compute Engine's load balancer resources take no such condition on every kind
# this role makes, so the Cloud Run administrator reaches the MCP host's services mcp and chat as
# well: it could change, replace or delete them, though any revision it deploys runs as zitadel@
# or zitadel-login@, the only accounts it may act as. The load balancer administrator reaches
# whatever load balancer the project holds; the MCP host has none, since Firebase Hosting fronts
# it. The project IAM administrator is held to the one project grant ../ makes, the Cloud SQL
# client role, so this account cannot grant itself or anyone else another role on the project.
#
# Secrets it administers through the role below, which leaves out reading a value: it makes the
# secrets, writes the generated values and sets who reads each. The one value it reads is
# zitadel-admin-key, for the zitadel root's provider, by a grant on that secret alone in
# ../secrets.tf. It still has two ways to every other ZITADEL value, which the roles it needs
# cannot close: setting a secret's policy is setting who reads it, so it could grant itself a
# zitadel-* secret; and with the Cloud Run administrator and the service account user on zitadel@
# it could deploy a revision that runs as zitadel@ and reads that account's secrets. What keeps
# either from happening unseen is that every grant and every service is declared in ../ and
# recorded in the audit log, and that only a push to main, after a reviewed merge, holds this
# account.
#
# idSecretsWithoutAccess, so the project's role list says whose it is; a custom role's id takes
# no hyphen.
resource "google_project_iam_custom_role" "secrets" {
  role_id     = "idSecretsWithoutAccess"
  title       = "Secret Manager administrator without access to values, for id.blust.ch"
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
  account_id   = "id-deploy"
  display_name = "id.blust.ch: Terraform apply, run by GitHub Actions on main"
  depends_on   = [google_project_service.bootstrap]
}

resource "google_project_iam_member" "deploy" {
  for_each = toset([
    "roles/run.admin",
    "roles/compute.loadBalancerAdmin",
    "roles/serviceusage.serviceUsageConsumer",
  ])
  project = local.d.project
  role    = each.value
  member  = google_service_account.deploy.member
}

resource "google_project_iam_member" "deploy_sql" {
  project = local.d.project
  role    = "roles/cloudsql.admin"
  member  = google_service_account.deploy.member
  condition {
    title       = "ZITADEL's instance only"
    description = "The Cloud SQL instance zitadel, which ../ makes, and no other."
    expression  = local.zitadel_sql
  }
}

resource "google_project_iam_member" "deploy_secrets" {
  project = local.d.project
  role    = google_project_iam_custom_role.secrets.name
  member  = google_service_account.deploy.member
  condition {
    title       = "ZITADEL's secrets only"
    description = "Secrets named zitadel-*, which ../ makes, and no other."
    expression  = local.zitadel_secrets
  }
}

resource "google_project_iam_member" "deploy_iam" {
  project = local.d.project
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = google_service_account.deploy.member
  condition {
    title       = "Grants only the Cloud SQL client role"
    description = "The one project grant ../ makes, to ZITADEL's identity."
    expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(['roles/cloudsql.client'])"
  }
}

# Deploying a service that runs as an account means acting as it; granted on the two accounts
# alone, so no revision CI deploys runs as any other account in the project.
resource "google_service_account_iam_member" "deploy_runs_as" {
  for_each = {
    zitadel = google_service_account.zitadel.name
    login   = google_service_account.login.name
  }
  service_account_id = each.value
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.deploy.member
}

resource "google_storage_bucket_iam_member" "deploy_state" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.deploy.member
}

resource "google_service_account_iam_member" "deploy_wif" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.main_pushes
}

# Plans a pull request: reads the configuration of everything ../ and ../../zitadel declare and
# the state they keep, and can change none of it; -lock=false in the plan is what lets it do
# without write on the bucket. id-deploy-plan, to pair with id-deploy and to read as this
# repository's beside the MCP host's terraform-plan@.
#
# It holds a viewer role per kind of resource ../ declares and not the project's viewer, because
# in a shared project the viewer reads the MCP host as well: its logs, its Firestore meter, and
# through each bucket's default policy, which lets the project's viewers read objects, the MCP
# host's state and the chat's reports. The roles it holds still reach the MCP host where no
# condition can narrow them: the Cloud Run viewer reads the configuration of the services mcp and
# chat, and the security reviewer every IAM policy in the project. The Secret Manager and Cloud
# SQL viewers are held to ZITADEL's by the same conditions as id-deploy's roles.
#
# The state holds no secret, since every generated value is ephemeral and written write-only. It
# reads no secret's value but one: zitadel-admin-key, granted on that secret alone in
# ../secrets.tf, because the zitadel root's plan has to sign in to ZITADEL to read what it holds,
# and that key is the instance's IAM_OWNER. So a pull request run holds that key while it runs,
# and nothing on the Google side beyond reading.
resource "google_service_account" "plan" {
  account_id   = "id-deploy-plan"
  display_name = "id.blust.ch: Terraform plan, run by GitHub Actions on a pull request"
  depends_on   = [google_project_service.bootstrap]
}

resource "google_project_iam_member" "plan" {
  for_each = toset([
    "roles/run.viewer",
    "roles/compute.viewer",
    "roles/iam.securityReviewer",
    "roles/serviceusage.serviceUsageConsumer",
  ])
  project = local.d.project
  role    = each.value
  member  = google_service_account.plan.member
}

resource "google_project_iam_member" "plan_sql" {
  project = local.d.project
  role    = "roles/cloudsql.viewer"
  member  = google_service_account.plan.member
  condition {
    title       = "ZITADEL's instance only"
    description = "The Cloud SQL instance zitadel, which ../ makes, and no other."
    expression  = local.zitadel_sql
  }
}

resource "google_project_iam_member" "plan_secrets" {
  project = local.d.project
  role    = "roles/secretmanager.viewer"
  member  = google_service_account.plan.member
  condition {
    title       = "ZITADEL's secrets only"
    description = "Secrets named zitadel-*, which ../ makes, and no other."
    expression  = local.zitadel_secrets
  }
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

output "workload_identity_provider" { value = google_iam_workload_identity_pool_provider.github.name }
output "deploy_service_account" { value = google_service_account.deploy.email }
output "plan_service_account" { value = google_service_account.plan.email }
output "zitadel_service_account" { value = google_service_account.zitadel.email }
output "login_service_account" { value = google_service_account.login.email }
output "state_bucket" { value = google_storage_bucket.state.name }

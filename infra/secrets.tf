# Every secret lives in Secret Manager and reaches a service as an environment variable, and none
# of them is in Terraform's state or plan. Four are generated here: the masterkey, which encrypts
# what ZITADEL stores and can never change once ZITADEL has started with it; the database
# password; the first admin's password, which ZITADEL asks to change at the first sign-in; and
# the login's cookie secret, which signs its session cookies. Each is an ephemeral value, made
# fresh for every run and never kept, written once as a write-only argument; Terraform writes it
# again only when its version below goes up. Seven are the owner's, made by hand once ZITADEL
# runs, as the README's owner's steps say: zitadel-login-token, the login's own token;
# zitadel-admin-key, the key the ../zitadel root signs in with; zitadel-google-client-secret,
# the secret of the Google OAuth client the ../zitadel root gives ZITADEL for sign-in with Google;
# zitadel-microsoft-client-secret, the secret of the Entra ID application it gives ZITADEL for
# sign-in with Microsoft; zitadel-github-client-secret, the secret of the GitHub OAuth App it
# gives ZITADEL for sign-in with GitHub; zitadel-smtp-password, the Gmail app password ZITADEL's
# mail signs in with; and zitadel-link-check-key, the key of the machine user link-check, which
# the link check reads users and adds links with. Terraform makes those seven secrets and never
# their values.
ephemeral "random_password" "masterkey" {
  length  = 32
  special = false
}

# The database password reaches two places in the same apply, the secret and the Cloud SQL user,
# and one ephemeral value is the same everywhere within a run, so the two agree. They move
# together: db_password_version is the one number both write against, and raising it rotates
# the password in both at once.
ephemeral "random_password" "db" {
  length  = 32
  special = false
}

# ZITADEL's default password policy asks for an upper, a lower, a digit and a symbol.
ephemeral "random_password" "admin" {
  length      = 24
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
}

ephemeral "random_password" "cookie" {
  length  = 48
  special = false
}

locals {
  db_password_version = 1
  generated = {
    "zitadel-masterkey"           = { value = ephemeral.random_password.masterkey.result, version = "1" }
    "zitadel-admin-password"      = { value = ephemeral.random_password.admin.result, version = "1" }
    "zitadel-login-cookie-secret" = { value = ephemeral.random_password.cookie.result, version = "1" }
  }
  by_hand = ["zitadel-login-token", "zitadel-admin-key", "zitadel-google-client-secret", "zitadel-microsoft-client-secret", "zitadel-github-client-secret", "zitadel-smtp-password", "zitadel-link-check-key"]
}

# Every secret's name starts with zitadel-, which is more than a habit: the project is shared with
# the MCP host, and the bootstrap holds CI's Secret Manager roles to secrets of that name, so CI
# could make a secret named otherwise but neither set who reads it nor write its value. tests/
# holds the names to it.
#
# A new masterkey would make everything ZITADEL has stored unreadable, so no apply may destroy a
# secret, nor the version of a value that is never meant to change: a plan that would is refused,
# and removing one is a change to this file first. The database password's version is the one
# exception, below, since rotating it replaces its version.
resource "google_secret_manager_secret" "s" {
  for_each  = toset(concat(keys(local.generated), ["zitadel-db-password"], local.by_hand))
  secret_id = each.key
  replication {
    auto {}
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_secret_manager_secret_version" "generated" {
  for_each               = toset(keys(local.generated))
  secret                 = google_secret_manager_secret.s[each.key].id
  secret_data_wo         = local.generated[each.key].value
  secret_data_wo_version = local.generated[each.key].version
  lifecycle {
    prevent_destroy = true
  }
}

# Raising db_password_version replaces this version, since the provider writes a write-only
# value again only as a new version, and sets the Cloud SQL user's password from the same run's
# value, so the rotation the comment above describes is one apply. It therefore carries no
# prevent_destroy; the old version is destroyed once the new one exists.
resource "google_secret_manager_secret_version" "db_password" {
  secret                 = google_secret_manager_secret.s["zitadel-db-password"].id
  secret_data_wo         = ephemeral.random_password.db.result
  secret_data_wo_version = tostring(local.db_password_version)
}

# Cloud Run refuses to deploy a service whose secret has no version, and the login reads its token
# on every start, so the token's secret starts with a placeholder the login runs with, unable to
# sign anyone in, until the owner adds the real token as the next version. The admin key and the
# two client secrets have none: nothing reads the key until ../zitadel applies, and nothing reads
# a client's secret until ../zitadel names that client.
resource "google_secret_manager_secret_version" "login_token_placeholder" {
  secret                 = google_secret_manager_secret.s["zitadel-login-token"].id
  secret_data_wo         = "placeholder"
  secret_data_wo_version = "1"
}

# The link check reads its key on every start too, so its secret starts the same way, with {}, the
# value the link check takes for no key: it starts, answers ZITADEL and links nobody until the
# owner adds the machine user's key as the next version. A link check that links nobody fails
# closed, since a sign-in it lets pass unlinked ends where it would without it.
resource "google_secret_manager_secret_version" "link_check_key_placeholder" {
  secret                 = google_secret_manager_secret.s["zitadel-link-check-key"].id
  secret_data_wo         = "{}"
  secret_data_wo_version = "1"
}

# Who reads which secret's value, one grant per secret and reader. Each service reads its own, the
# link check its key and nothing else. That key is a user manager's of blust.ch, which holds the
# owner's IAM_OWNER user and the service user terraform, so it may link an account to the owner's
# user or add a key to terraform, and is worth what the admin key is.
# The ../zitadel root signs in with the admin key: id-deploy@ when it applies on main, and
# id-deploy-plan@ when it plans a pull request, since a plan reads what ZITADEL holds and cannot
# without signing in. That makes every pull request run of this repository, Dependabot's
# included, a holder of the instance's IAM_OWNER key for the length of the run; it is the price of
# a plan on every pull request. The Google, Microsoft and GitHub client secrets and the Gmail
# app password are read by the same two, for the same reason: the ../zitadel root gives each to
# ZITADEL as a write-only argument, which a plan reads too. Those five are the only secrets the
# plan identity reads. The accounts are the bootstrap's, named id- there because the project is
# shared with the MCP host.
locals {
  plan_member   = "serviceAccount:id-deploy-plan@${local.d.project}.iam.gserviceaccount.com"
  deploy_member = "serviceAccount:id-deploy@${local.d.project}.iam.gserviceaccount.com"
  readers = {
    "zitadel-masterkey/zitadel"         = { secret = "zitadel-masterkey", member = local.zitadel_member }
    "zitadel-db-password/zitadel"       = { secret = "zitadel-db-password", member = local.zitadel_member }
    "zitadel-admin-password/zitadel"    = { secret = "zitadel-admin-password", member = local.zitadel_member }
    "zitadel-login-token/login"         = { secret = "zitadel-login-token", member = local.login_member }
    "zitadel-login-cookie-secret/login" = { secret = "zitadel-login-cookie-secret", member = local.login_member }
    "zitadel-link-check-key/link-check" = { secret = "zitadel-link-check-key", member = local.link_check_member }
    "zitadel-admin-key/deploy"          = { secret = "zitadel-admin-key", member = local.deploy_member }
    "zitadel-admin-key/deploy-plan"     = { secret = "zitadel-admin-key", member = local.plan_member }

    "zitadel-google-client-secret/deploy"         = { secret = "zitadel-google-client-secret", member = local.deploy_member }
    "zitadel-google-client-secret/deploy-plan"    = { secret = "zitadel-google-client-secret", member = local.plan_member }
    "zitadel-microsoft-client-secret/deploy"      = { secret = "zitadel-microsoft-client-secret", member = local.deploy_member }
    "zitadel-microsoft-client-secret/deploy-plan" = { secret = "zitadel-microsoft-client-secret", member = local.plan_member }
    "zitadel-github-client-secret/deploy"         = { secret = "zitadel-github-client-secret", member = local.deploy_member }
    "zitadel-github-client-secret/deploy-plan"    = { secret = "zitadel-github-client-secret", member = local.plan_member }
    "zitadel-smtp-password/deploy"                = { secret = "zitadel-smtp-password", member = local.deploy_member }
    "zitadel-smtp-password/deploy-plan"           = { secret = "zitadel-smtp-password", member = local.plan_member }
  }
}

resource "google_secret_manager_secret_iam_member" "reader" {
  for_each  = local.readers
  secret_id = google_secret_manager_secret.s[each.value.secret].id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}

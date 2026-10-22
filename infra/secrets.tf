# Every secret lives in Secret Manager and reaches a service as an environment variable. Four are
# generated here: the masterkey, which encrypts what ZITADEL stores and can never change once
# ZITADEL has started with it; the database password; the first admin's password, which ZITADEL
# asks to change at the first sign-in; and the login's cookie secret, which signs its session
# cookies. Two are the owner's, made by hand once ZITADEL runs, as the README's owner's steps say:
# zitadel-login-token, the login's own token, and zitadel-admin-key, the key the ../zitadel root
# signs in with. Terraform makes those two secrets and never their values.
resource "random_password" "masterkey" {
  length  = 32
  special = false
  lifecycle {
    prevent_destroy = true
  }
}

resource "random_password" "db" {
  length  = 32
  special = false
}

# ZITADEL's default password policy asks for an upper, a lower, a digit and a symbol.
resource "random_password" "admin" {
  length      = 24
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
}

resource "random_password" "cookie" {
  length  = 48
  special = false
}

locals {
  generated = {
    "zitadel-masterkey"           = random_password.masterkey.result
    "zitadel-db-password"         = random_password.db.result
    "zitadel-admin-password"      = random_password.admin.result
    "zitadel-login-cookie-secret" = random_password.cookie.result
  }
  by_hand = ["zitadel-login-token", "zitadel-admin-key"]
}

resource "google_secret_manager_secret" "s" {
  for_each  = toset(concat(keys(local.generated), local.by_hand))
  secret_id = each.key
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "generated" {
  for_each    = local.generated
  secret      = google_secret_manager_secret.s[each.key].id
  secret_data = each.value
}

# Cloud Run refuses to deploy a service whose secret has no version, and the login reads its token
# on every start, so the token's secret starts with a placeholder the login runs with, unable to
# sign anyone in, until the owner adds the real token as the next version. Terraform never reads
# the value again. The admin key has no placeholder: nothing reads it until ../zitadel applies.
resource "google_secret_manager_secret_version" "login_token_placeholder" {
  secret      = google_secret_manager_secret.s["zitadel-login-token"].id
  secret_data = "placeholder"
  lifecycle {
    ignore_changes = [secret_data]
  }
}

locals {
  readers = {
    "zitadel-masterkey"           = google_service_account.zitadel.member
    "zitadel-db-password"         = google_service_account.zitadel.member
    "zitadel-admin-password"      = google_service_account.zitadel.member
    "zitadel-login-token"         = google_service_account.login.member
    "zitadel-login-cookie-secret" = google_service_account.login.member
  }
}

resource "google_secret_manager_secret_iam_member" "run" {
  for_each  = local.readers
  secret_id = google_secret_manager_secret.s[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value
}

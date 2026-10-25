# Sign in with Google, as another way in for an account the owner has made, never as a way to
# open one: the privacy pages say accounts are by invitation only, and three settings keep that
# true together. The login policy in policy.tf keeps registration off, so nobody makes an account
# with a password; this provider allows no creation and creates nobody on its own, so a Google
# account that matches no user ends on the login's account-not-found page; and auto-linking by
# email joins a Google account to a user only when Google says the address is verified and a
# user with that very address exists, which only the owner can make. Linking is allowed, since
# ZITADEL's login links an account, by hand or automatically, only for a provider that allows it.
# The login v2 this instance runs checks the verified address before it searches for the user
# (apps/login/src/lib/server/idp-intent.ts at ZITADEL v4.19.5, handleAutoLinking). Google does
# not update the user: the account's name and address are what the owner gave it.
#
# The client's id is no secret, since every Google sign-in page names it in its address, so it
# is this variable's default once the owner has made the client, as the README's owner's steps
# say; until then it is null and the provider is not made. The client's secret is not in this
# repository or the state: it is read for each run from the secret zitadel-google-client-secret,
# which ../infra makes empty and the owner fills, as an ephemeral value, and reaches ZITADEL as
# the provider's write-only client_secret. The state keeps only client_secret_hash, the
# provider's stretched one-way hash, which lets a rotated secret show as a change.
variable "google_client_id" {
  type    = string
  default = "38003987140-5ijibantfd0njk4576bj8qm062nktj31.apps.googleusercontent.com"
  validation {
    condition     = var.google_client_id == null || can(regex("^[0-9]+-[a-z0-9]+\\.apps\\.googleusercontent\\.com$", var.google_client_id))
    error_message = "google_client_id is the Google OAuth client's id, of the form 123-abc.apps.googleusercontent.com, or null."
  }
}

# A secret given directly, which only the tests in tests/ do, for the reason main.tf gives for
# admin_key; CI never sets it, so the real secret is only ever the ephemeral value below. It
# cannot itself be ephemeral, since it decides whether the secret is read, and Terraform takes no
# ephemeral value in a count.
variable "google_client_secret" {
  type      = string
  default   = null
  sensitive = true
}

locals {
  google = var.google_client_id != null
}

ephemeral "google_secret_manager_secret_version" "google_client_secret" {
  count  = local.google && var.google_client_secret == null ? 1 : 0
  secret = "zitadel-google-client-secret"
}

resource "zitadel_idp_google" "google" {
  count         = local.google ? 1 : 0
  name          = "Google"
  client_id     = var.google_client_id
  client_secret = var.google_client_secret != null ? var.google_client_secret : ephemeral.google_secret_manager_secret_version.google_client_secret[0].secret_data
  scopes        = ["openid", "profile", "email"]

  is_linking_allowed  = true
  is_creation_allowed = false
  is_auto_creation    = false
  is_auto_update      = false
  auto_linking        = "AUTO_LINKING_OPTION_EMAIL"
}

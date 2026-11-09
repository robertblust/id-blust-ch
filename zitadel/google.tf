# Sign in with Google, a way into an account the owner has made, and a way to open one only
# while open_sign_up in policy.tf is on, which lets registration and every provider's creation of
# accounts on together. With it off, this provider allows no creation, so a Google account that
# the link check links to no user ends on the login's account-not-found page. With it on, a
# person with no account is offered one, and the provider never creates it on its own, so they
# see the registration form before an account is made.
#
# ZITADEL links no Google account by address itself: login v2 would link into whatever account
# holds the address, whether or not that account ever verified it (handleAutoLinking in
# apps/login/src/lib/server/idp-intent.ts at ZITADEL v4.19.5), and once anyone may open an
# account that is a takeover, as link-check.tf says. So auto-linking is off, and the link check
# links a Google sign-in to the one account holding its address only when Google says the
# address is verified and that account's address is verified too. Linking is allowed, since
# ZITADEL's login links an account, as an invited person does from the invitation, only for a
# provider that allows it. Google does not update the user: the account keeps the name and
# address it was made with.
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
  is_creation_allowed = var.open_sign_up
  is_auto_creation    = false
  is_auto_update      = false
  auto_linking        = "AUTO_LINKING_OPTION_UNSPECIFIED"
}

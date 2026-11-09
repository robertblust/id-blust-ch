# Sign in with GitHub, beside Google and Microsoft, a way into an account the owner has made, and
# a way to open one only while open_sign_up in policy.tf is on, as theirs are. With it off, this
# provider allows no creation, so a GitHub account that the link check links to no user ends on
# the login's account-not-found page; with it on, a person with no account is offered one, and the
# provider never creates it on its own.
#
# ZITADEL calls every address it takes from GitHub verified without asking GitHub: IsEmailVerified
# returns true (internal/idp/providers/github/github.go at ZITADEL v4.19.5), and this resource has
# no switch to say otherwise. The address is the profile's public email, or, where that is empty,
# the one that is both primary and verified in the account's list, which the scope user:email lets
# ZITADEL read (internal/idp/providers/github/session.go at the same release). So the link check
# proves the address itself, per sign-in, with the access token ZITADEL hands it in the answer: it
# counts only when GitHub's GET /user/emails holds it with verified true. A proven address links
# under link-check.tf's rule, and a new account opened with it needs no code. An unproven one
# links nothing, and the link check sets it to unverified, so its new account gets the login's
# code; for this provider alone the link check undoes what ZITADEL claimed. While the link check
# is down, ZITADEL's claim stands for a new account, and nothing links on it;
# docs/superpowers/specs/2026-11-09-github-sign-in-design.md says what that leaves open and what
# the owner checks before naming the client. Linking is allowed, as for the other two, and GitHub
# does not update the user: the account keeps the name and address it was made with.
#
# user:email is the one scope: ZITADEL reads GitHub's /user with none, and /user/emails, which
# both ZITADEL and the link check read, needs user:email. read:user would also let the token read
# the profile's private fields, which nothing here reads.
#
# The client's id is no secret, since every GitHub sign-in page names it in its address, so it is
# this variable's default once the owner has made the OAuth App, as the README's owner's steps
# say; until then it is null and the provider is not made. The client's secret is read for each
# run from the secret zitadel-github-client-secret, which ../infra makes empty and the owner fills,
# as an ephemeral value, and reaches ZITADEL as the provider's write-only client_secret, as
# Google's does.
variable "github_client_id" {
  type    = string
  default = null
  validation {
    condition     = var.github_client_id == null || can(regex("^(Ov23[A-Za-z0-9]{16}|[0-9a-f]{20})$", var.github_client_id))
    error_message = "github_client_id is the GitHub OAuth App's client id, Ov23 and sixteen letters or digits, or twenty hexadecimal digits for an older app, or null."
  }
}

# A secret given directly, which only the tests in tests/ do, for the reason google.tf gives for
# google_client_secret.
variable "github_client_secret" {
  type      = string
  default   = null
  sensitive = true
}

locals {
  github = var.github_client_id != null
}

ephemeral "google_secret_manager_secret_version" "github_client_secret" {
  count  = local.github && var.github_client_secret == null ? 1 : 0
  secret = "zitadel-github-client-secret"
}

resource "zitadel_idp_github" "github" {
  count         = local.github ? 1 : 0
  name          = "GitHub"
  client_id     = var.github_client_id
  client_secret = var.github_client_secret != null ? var.github_client_secret : ephemeral.google_secret_manager_secret_version.github_client_secret[0].secret_data
  scopes        = ["user:email"]

  is_linking_allowed  = true
  is_creation_allowed = var.open_sign_up
  is_auto_creation    = false
  is_auto_update      = false
  auto_linking        = "AUTO_LINKING_OPTION_UNSPECIFIED"
}

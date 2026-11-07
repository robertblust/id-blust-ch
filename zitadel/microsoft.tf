# Sign in with Microsoft, beside Google, as another way in for an account the owner has made,
# never as a way to open one. Like Google's, this provider allows no creation and creates nobody
# on its own, so a Microsoft account that matches no user ends on the login's account-not-found
# page, and the login policy in policy.tf keeps registration off.
#
# It accepts work and school accounts of any organization and personal Microsoft accounts alike,
# Microsoft's common tenant, since the readers the owner invites hold both. That is why it links
# to no user by itself. ZITADEL takes the address from Microsoft Graph's mail, falling back to the
# user principal name, and Microsoft says nothing of whether the address is verified, so ZITADEL
# has only a switch that calls every address verified (internal/idp/providers/azuread/azuread.go
# at ZITADEL v4.19.5, WithEmailVerified). With the common tenant, the administrator of any
# organization's directory can set a user's mail to any address, so auto-linking by email would
# let them sign in as whoever the owner invited under that address. The address is therefore
# left unverified and auto-linking off: login v2 links by email only to a verified address, and by
# username with no check at all (apps/login/src/lib/server/idp-intent.ts at ZITADEL v4.19.5,
# handleAutoLinking), so neither is set.
#
# A person links Microsoft to their user themselves, which is why linking is allowed: login v2
# links a provider to a user only from a session that proved who the user is, either by a factor
# the user already holds, Google or a passkey, or by the invitation's code for a user who holds
# none yet (resolveUserIdFromSession in the same file). So an invited person accepts the
# invitation and chooses Microsoft where the login asks how they will sign in, and a person who
# already signs in another way opens the same page, /ui/v2/login/authenticator/set, in the browser
# they signed in with, and the login mails them a code before it offers Microsoft
# (apps/login/src/app/(login)/authenticator/set/page.tsx at ZITADEL v4.19.5). Microsoft does not
# update the user: the account's name and address are what the owner gave it.
#
# The client's id is no secret, since every Microsoft sign-in page names it in its address, so it
# is this variable's default once the owner has made the application in Entra ID, as the README's
# owner's steps say; until then it is null and the provider is not made. The client's secret is
# read for each run from the secret zitadel-microsoft-client-secret, which ../infra makes empty and
# the owner fills, as an ephemeral value, and reaches ZITADEL as the provider's write-only
# client_secret, as Google's does.
variable "microsoft_client_id" {
  type    = string
  default = "63c23dec-2f51-4e39-a221-c7cfc3782d34"
  validation {
    condition     = var.microsoft_client_id == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.microsoft_client_id))
    error_message = "microsoft_client_id is the Entra ID application's client id, a GUID in lower case, or null."
  }
}

# A secret given directly, which only the tests in tests/ do, for the reason google.tf gives for
# google_client_secret.
variable "microsoft_client_secret" {
  type      = string
  default   = null
  sensitive = true
}

locals {
  microsoft = var.microsoft_client_id != null
}

ephemeral "google_secret_manager_secret_version" "microsoft_client_secret" {
  count  = local.microsoft && var.microsoft_client_secret == null ? 1 : 0
  secret = "zitadel-microsoft-client-secret"
}

# User.Read lets ZITADEL read the user from Microsoft Graph, which is where it takes the name and
# address from; phone, which ZITADEL asks for when no scopes are given, is left out.
resource "zitadel_idp_azure_ad" "microsoft" {
  count         = local.microsoft ? 1 : 0
  name          = "Microsoft"
  client_id     = var.microsoft_client_id
  client_secret = var.microsoft_client_secret != null ? var.microsoft_client_secret : ephemeral.google_secret_manager_secret_version.microsoft_client_secret[0].secret_data
  scopes        = ["openid", "profile", "email", "User.Read"]
  tenant_type   = "AZURE_AD_TENANT_TYPE_COMMON"

  email_verified      = false
  is_linking_allowed  = true
  is_creation_allowed = false
  is_auto_creation    = false
  is_auto_update      = false
  auto_linking        = "AUTO_LINKING_OPTION_UNSPECIFIED"
}

# Sign in with Microsoft, beside Google, a way into an account the owner has made, and a way to
# open one only while open_sign_up in policy.tf is on, as Google's is. With it off, this provider
# allows no creation, so a Microsoft account that the link check links to no user ends on the
# login's account-not-found page; with it on, a person with no account is offered one, and the
# provider never creates it on its own.
#
# It accepts work and school accounts of any organization and personal Microsoft accounts alike,
# Microsoft's common tenant, since the readers hold both. That is why its address is never taken
# as verified. ZITADEL takes the address from Microsoft Graph's mail, falling back to the user
# principal name, and Microsoft says nothing of whether the address is verified, so ZITADEL has
# only a switch that calls every address verified or none
# (internal/idp/providers/azuread/azuread.go at ZITADEL v4.19.5, WithEmailVerified). With the
# common tenant it also returns before it keeps Microsoft's ID token (FetchUser in
# internal/idp/providers/azuread/session.go at the same release), so the token's xms_edov claim,
# which would say whether the address is verified, never arrives. The administrator of any
# organization's directory can set a user's mail to any address, so a link on that address would
# let them sign in as whoever holds it here. The address is therefore left unverified and
# auto-linking off, and the link check alone decides, per sign-in, with the access token ZITADEL
# hands it in the answer and the User.Read this provider asks for. A work or school account's
# address is proven when its domain is one the person's own organization has verified
# (GET /organization with verifiedDomains, Microsoft Graph's "Get organization", read Nov 8,
# 2026), so a guest's own address in someone else's organization is not; a personal account's is
# proven when that call fails with a client error (4xx) and GET /me answers with an id of 16
# hexadecimal characters, the form of a personal account's id. The address that counts for a
# personal account is its sign-in name, Graph's userPrincipalName, since Microsoft verified it when
# the account was made or the alias added; its mail may be a stand-in Microsoft generated, so the
# answer's address must equal the mail or the sign-in name, the sign-in name must look like an
# address, and the sign-in name replaces the answer's address from then on. A work or school
# account's mail, or the user principal name where mail is empty, must equal the answer's address.
# Anything else, an error or a timeout included, is not proven; ../link-check/lib/prove.mjs holds
# these rules. A proven address is linked under link-check.tf's rule, and a new account opened
# with it needs no code; an unproven one links nothing, and its new account gets the login's code.
#
# Linking is allowed, so a link the link check refuses is made one of two ways. An invited person
# makes it themselves: login v2 links a provider only from a session that proved who the user
# is, and the invitation's code proves it for a user who holds no way in yet
# (resolveUserIdFromSession in apps/login/src/lib/server/idp-intent.ts at ZITADEL v4.19.5), so
# they choose Microsoft where the login asks how they will sign in. A person who already signs in
# with Google or a passkey cannot: the login offers a link only after a code it mails, and it
# mails one only to a user with no way in (verify.ts and
# apps/login/src/app/(login)/authenticator/set/page.tsx at ZITADEL v4.19.5), so for them it
# answers "User is already verified!". The owner makes that link instead, with link-idp.py, from
# the external id ZITADEL kept of the person's one attempt with Microsoft, as the README's step 26
# says. Microsoft does not update the user: the account keeps the name and address it was made
# with.
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
  is_creation_allowed = var.open_sign_up
  is_auto_creation    = false
  is_auto_update      = false
  auto_linking        = "AUTO_LINKING_OPTION_UNSPECIFIED"
}

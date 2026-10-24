# One application per site, a public client in the browser: the chat panel signs a reader in with
# the authorization code and PKCE and holds no secret, which a page anyone can read could not
# keep. Access tokens are JWTs carrying the roles, so the chat server checks a token against the
# issuer's published keys without asking ZITADEL; the ID token carries them too, and the reader's
# name, for the panel to say who is signed in and what it may offer. The site's origin is both
# where the login returns and where a sign-out lands.
resource "zitadel_application_oidc" "site" {
  for_each   = local.sites
  org_id     = local.blust_ch
  project_id = zitadel_project.chat.id
  name       = each.key

  app_type         = "OIDC_APP_TYPE_USER_AGENT"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_NONE"
  grant_types      = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  response_types   = ["OIDC_RESPONSE_TYPE_CODE"]

  access_token_type           = "OIDC_TOKEN_TYPE_JWT"
  access_token_role_assertion = true
  id_token_role_assertion     = true
  id_token_userinfo_assertion = true

  redirect_uris             = ["${each.value.origin}/"]
  post_logout_redirect_uris = ["${each.value.origin}/"]
}

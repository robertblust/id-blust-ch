# What this root makes, planned and applied against mocked providers, for both grant models: the
# roles, the grants, the applications and the sign_in block each site's chat.json copies; and
# sign-in with Google, absent while it has no client and, with one, a way in that opens no
# account. The keys are passed as admin_key and google_client_secret, since a mock provider
# cannot stand in for the ephemeral secret reads, and the Google provider is the real one with a
# token that is never sent: with both set, this root asks Google for nothing.
provider "google" {
  project      = "test"
  access_token = "unused"
}

mock_provider "zitadel" {
  mock_data "zitadel_orgs" {
    defaults = { ids = ["100"] }
  }
  mock_resource "zitadel_project" {
    defaults = { id = "200" }
  }
  mock_resource "zitadel_org" {
    defaults = { id = "300" }
  }
  mock_resource "zitadel_application_oidc" {
    defaults = { client_id = "client" }
  }
  mock_resource "zitadel_idp_google" {
    defaults = { id = "400" }
  }
}

variables {
  admin_key = "{}"
  # The client id the root names by default is the live one; a run that is not about Google
  # names none, so no run reads the real secret, and the google run names its own.
  google_client_id = null
}

run "cross_organization" {
  command = apply

  assert {
    condition     = length(zitadel_email_provider_smtp.gmail) == 0
    error_message = "Without the mail's account ZITADEL has no mail provider."
  }
  assert {
    condition     = join(",", sort([zitadel_default_invite_user_message_text.en.language, zitadel_default_invite_user_message_text.de.language, zitadel_default_verify_email_message_text.en.language, zitadel_default_verify_email_message_text.de.language])) == "de,de,en,en" && zitadel_default_hosted_login_translation.en.language == "en" && zitadel_default_hosted_login_translation.de.language == "de"
    error_message = "The invitation, the verification mail and the login's texts are written in English and German."
  }
  assert {
    condition = alltrue([for t in [
      zitadel_default_invite_user_message_text.de.text, zitadel_default_invite_user_message_text.de.subject,
      zitadel_default_verify_email_message_text.de.text, zitadel_default_verify_email_message_text.de.subject,
      zitadel_default_hosted_login_translation.de.translations,
    ] : !strcontains(t, "ß")])
    error_message = "Swiss Standard German writes ss, never ß."
  }
  assert {
    condition     = strcontains(zitadel_default_verify_email_message_text.en.text, "{{.Code}}") && strcontains(zitadel_default_verify_email_message_text.de.text, "{{.Code}}")
    error_message = "The verification mail carries its code, for a reader whose mail client hides the button."
  }

  assert {
    condition     = join(",", sort(keys(zitadel_project_role.role))) == "fable,haiku,opus,sonnet-5-5"
    error_message = "The project holds the four model roles."
  }
  assert {
    condition     = length(zitadel_project_grant.site) == 2 && alltrue([for g in zitadel_project_grant.site : length(g.role_keys) == 4])
    error_message = "The project is granted to the two other organizations with every role."
  }
  assert {
    condition     = output.sign_in["https://blust.ch"] == { issuer = "https://id.blust.ch", project_id = "200", org_id = "100", client_id = "client" }
    error_message = "blust.ch's sign_in names the issuer, the project, its own organization and its client."
  }
  assert {
    condition     = output.sign_in["https://guestgraph.io"].org_id == "300" && !contains(keys(output.sign_in["https://guestgraph.io"]), "role_prefix")
    error_message = "Another site's sign_in names its own organization and no role prefix."
  }
  assert {
    condition     = join(",", zitadel_application_oidc.site["companygraph.io"].redirect_uris) == "https://companygraph.io/" && zitadel_application_oidc.site["companygraph.io"].auth_method_type == "OIDC_AUTH_METHOD_TYPE_NONE"
    error_message = "Each site's application is a public client returning to the site's origin."
  }
  assert {
    condition     = zitadel_default_login_policy.this.allow_register == false && zitadel_default_login_policy.this.hide_password_reset == true
    error_message = "Nobody registers, and no reset link promises a mail that never comes."
  }
  assert {
    condition     = length(zitadel_idp_google.google) == 0 && zitadel_default_login_policy.this.allow_external_idp == false && length(coalesce(zitadel_default_login_policy.this.idps, [])) == 0
    error_message = "Without a Google client there is no Google provider, and no external sign-in."
  }
}

run "google" {
  command = apply

  variables {
    google_client_id     = "123456789012-abcdefghijklmnopqrstuvwxyz012345.apps.googleusercontent.com"
    google_client_secret = "unused"
  }

  assert {
    condition     = zitadel_idp_google.google[0].is_creation_allowed == false && zitadel_idp_google.google[0].is_auto_creation == false
    error_message = "Google opens no account: it allows no creation and creates nobody on its own."
  }
  assert {
    condition     = zitadel_idp_google.google[0].is_linking_allowed == true && zitadel_idp_google.google[0].auto_linking == "AUTO_LINKING_OPTION_EMAIL" && zitadel_idp_google.google[0].is_auto_update == false
    error_message = "Google links onto an existing user by verified email, and leaves the user's data as the owner made it."
  }
  assert {
    condition     = join(",", sort(tolist(zitadel_idp_google.google[0].scopes))) == "email,openid,profile"
    error_message = "Google is asked for openid, profile and email only."
  }
  assert {
    condition     = zitadel_idp_google.google[0].client_secret == null
    error_message = "The client secret is write-only and not in the state."
  }
  assert {
    condition     = zitadel_default_login_policy.this.allow_external_idp == true && join(",", tolist(zitadel_default_login_policy.this.idps)) == "400"
    error_message = "The login offers external sign-in, and Google alone."
  }
  assert {
    condition     = zitadel_default_login_policy.this.allow_register == false
    error_message = "Registration stays off with Google on."
  }
  assert {
    condition     = length(coalesce(zitadel_default_login_policy.this.second_factors, [])) == 0 && zitadel_default_login_policy.this.force_mfa == false && zitadel_default_login_policy.this.force_mfa_local_only == false
    error_message = "No second factor can be added or is forced, so none stands in front of a Google sign-in."
  }
  assert {
    condition     = zitadel_default_login_policy.this.passwordless_type == "PASSWORDLESS_TYPE_ALLOWED"
    error_message = "Passkeys stay allowed."
  }
}

run "mail" {
  command = apply

  variables {
    smtp_user     = "mail@example.com"
    smtp_password = "unused"
  }

  assert {
    condition     = zitadel_email_provider_smtp.gmail[0].host == "smtp.gmail.com:587" && zitadel_email_provider_smtp.gmail[0].tls == true && zitadel_email_provider_smtp.gmail[0].set_active == true
    error_message = "ZITADEL's mail goes out through Gmail's SMTP server over TLS, and that provider is the active one."
  }
  assert {
    condition     = zitadel_email_provider_smtp.gmail[0].sender_address == "no-reply@blust.ch" && zitadel_email_provider_smtp.gmail[0].sender_name == "blust.ch"
    error_message = "The mail comes from no-reply@blust.ch."
  }
  assert {
    condition     = zitadel_email_provider_smtp.gmail[0].password == null
    error_message = "The app password is write-only and not in the state."
  }
}

run "not_an_smtp_user" {
  command = plan

  variables {
    smtp_user = "not an address"
  }

  expect_failures = [var.smtp_user]
}

run "not_a_google_client_id" {
  command = plan

  variables {
    google_client_id = "my-client"
  }

  expect_failures = [var.google_client_id]
}

run "role_per_site" {
  command = apply

  variables {
    role_per_site = true
  }

  assert {
    condition     = length(zitadel_project_role.role) == 12 && contains(keys(zitadel_project_role.role), "companygraph-io-opus")
    error_message = "Each site has a role per model."
  }
  assert {
    condition     = length(zitadel_project_grant.site) == 0
    error_message = "No organization is granted the project."
  }
  assert {
    condition     = output.sign_in["https://companygraph.io"].role_prefix == "companygraph-io-" && output.sign_in["https://companygraph.io"].org_id == "100"
    error_message = "A site's sign_in names its role prefix and blust.ch, where every grant is."
  }
}

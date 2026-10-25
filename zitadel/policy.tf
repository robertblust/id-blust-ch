# The instance's login, which every organization inherits while it sets none of its own. The login
# cannot know a reader's organization before they sign in, so it is one login in blust.ch's look
# for all three sites, and not a look per site.
#
# Login v2 is the container ../infra runs under /ui/v2/login. The instance starts on the built-in
# login, so the owner can sign in and make the login's token, and this turns v2 on for every
# application once the token is in Secret Manager, which the README's owner's steps put before
# this root's first apply.
resource "zitadel_instance_features" "this" {
  login_v2 {
    required = true
    base_uri = "${local.issuer}/ui/v2/login"
  }
}

# Nobody registers: the owner adds each person. A password signs in, and a passkey may replace
# it; a second factor is an authenticator app or a security key, never a text message, since no
# message provider is set up. No mail provider is set up either, so a reset link would promise a
# mail that never comes: the link stays hidden until one is, and until then the owner creates a
# person with an initial password and gives it to them in person. Once google.tf has a client,
# Google is a second way in for those people, and external sign-in is allowed for that provider
# alone; until then it stays off. The lifetimes are ZITADEL's defaults.
locals {
  login = {
    user_login                    = true
    allow_register                = false
    allow_external_idp            = local.google
    idps                          = zitadel_idp_google.google[*].id
    passwordless_type             = "PASSWORDLESS_TYPE_ALLOWED"
    hide_password_reset           = true
    ignore_unknown_usernames      = true
    allow_domain_discovery        = false
    disable_login_with_email      = false
    disable_login_with_phone      = true
    default_redirect_uri          = "https://blust.ch/"
    password_check_lifetime       = "240h0m0s"
    external_login_check_lifetime = "240h0m0s"
    multi_factor_check_lifetime   = "12h0m0s"
    mfa_init_skip_lifetime        = "720h0m0s"
    second_factor_check_lifetime  = "18h0m0s"
    second_factors                = ["SECOND_FACTOR_TYPE_OTP", "SECOND_FACTOR_TYPE_U2F"]
    multi_factors                 = ["MULTI_FACTOR_TYPE_U2F_WITH_VERIFICATION"]
  }
}

resource "zitadel_default_login_policy" "this" {
  user_login                    = local.login.user_login
  allow_register                = local.login.allow_register
  allow_external_idp            = local.login.allow_external_idp
  idps                          = local.login.idps
  force_mfa                     = false
  force_mfa_local_only          = false
  passwordless_type             = local.login.passwordless_type
  hide_password_reset           = local.login.hide_password_reset
  ignore_unknown_usernames      = local.login.ignore_unknown_usernames
  allow_domain_discovery        = local.login.allow_domain_discovery
  disable_login_with_email      = local.login.disable_login_with_email
  disable_login_with_phone      = local.login.disable_login_with_phone
  default_redirect_uri          = local.login.default_redirect_uri
  password_check_lifetime       = local.login.password_check_lifetime
  external_login_check_lifetime = local.login.external_login_check_lifetime
  multi_factor_check_lifetime   = local.login.multi_factor_check_lifetime
  mfa_init_skip_lifetime        = local.login.mfa_init_skip_lifetime
  second_factor_check_lifetime  = local.login.second_factor_check_lifetime
  second_factors                = local.login.second_factors
  multi_factors                 = local.login.multi_factors
}

# blust.ch, where the owner's account lives, holds a login of its own that forces a second factor
# on every sign-in, Google's included, so a Google account taken over does not alone reach the
# instance's admin. The owner first set it in the console, which copies the instance's login into
# the organization at that moment and no longer follows it: the copy kept external sign-in off
# after the instance turned it on, and the login, which asks blust.ch's settings whenever a
# sign-in names no organization, showed no Google button. So it is declared here, from the same
# settings as the instance's, and differs in the second factor alone. The import takes over the
# console's copy rather than failing on a second one.
import {
  to = zitadel_login_policy.blust_ch
  id = local.blust_ch
}

resource "zitadel_login_policy" "blust_ch" {
  org_id                        = local.blust_ch
  user_login                    = local.login.user_login
  allow_register                = local.login.allow_register
  allow_external_idp            = local.login.allow_external_idp
  idps                          = local.login.idps
  force_mfa                     = true
  force_mfa_local_only          = false
  passwordless_type             = local.login.passwordless_type
  hide_password_reset           = local.login.hide_password_reset
  ignore_unknown_usernames      = local.login.ignore_unknown_usernames
  allow_domain_discovery        = local.login.allow_domain_discovery
  disable_login_with_email      = local.login.disable_login_with_email
  disable_login_with_phone      = local.login.disable_login_with_phone
  default_redirect_uri          = local.login.default_redirect_uri
  password_check_lifetime       = local.login.password_check_lifetime
  external_login_check_lifetime = local.login.external_login_check_lifetime
  multi_factor_check_lifetime   = local.login.multi_factor_check_lifetime
  mfa_init_skip_lifetime        = local.login.mfa_init_skip_lifetime
  second_factor_check_lifetime  = local.login.second_factor_check_lifetime
  second_factors                = local.login.second_factors
  multi_factors                 = local.login.multi_factors
}

# blust.ch's colors, from the design tokens of robertblust/design: the ground, the ink, the link
# color as the primary and the warning color, for the light theme and the dark one, which the
# reader's system chooses between as it does on blust.ch. The mark is blust.ch's favicon, as the
# logo and as the icon, on both themes, since it carries its own ground.
locals {
  mark = "${path.module}/branding/mark.svg"
}

resource "zitadel_default_label_policy" "this" {
  background_color = "#FAF9F5"
  font_color       = "#16181D"
  primary_color    = "#3A6DA6"
  warn_color       = "#BC3924"

  background_color_dark = "#0C0E13"
  font_color_dark       = "#EFEDE8"
  primary_color_dark    = "#7FA3D8"
  warn_color_dark       = "#E0705E"

  logo_path      = local.mark
  logo_hash      = filemd5(local.mark)
  logo_dark_path = local.mark
  logo_dark_hash = filemd5(local.mark)
  icon_path      = local.mark
  icon_hash      = filemd5(local.mark)
  icon_dark_path = local.mark
  icon_dark_hash = filemd5(local.mark)

  theme_mode             = "THEME_MODE_AUTO"
  hide_login_name_suffix = true
  disable_watermark      = false
  set_active             = true
}

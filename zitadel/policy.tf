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

# Nobody registers: the owner adds each person, and nobody signs in with a password. ZITADEL
# cannot allow passkeys and forbid passwords, since login v2 lets a passkey sign in only where
# local sign-in, which is passwords too, is on (apps/login/src/lib/server/loginname.ts at ZITADEL
# v4.19.5), so the setting allows both and the accounts keep it passwordless: the owner makes
# each person with a verified address and no password, the person signs in with Google, which
# links to that address, and may add a passkey. ZITADEL cannot remove a password either, so an
# account that once had one has it replaced by a random one nobody keeps. No mail provider is
# set up, so the login's reset link stays hidden.
#
# No second factor can be added, neither an authenticator app nor a security key: login v2 asks
# for any second factor a user holds after every sign-in but a passkey's, Google's included,
# whatever the settings force (checkMFAFactors in apps/login/src/lib/server/idp.ts at ZITADEL
# v4.19.5), so one factor added once would stand in front of Google for good. Google's own two
# steps guard a Google sign-in, and a passkey is two factors by itself. External sign-in is
# allowed for Google alone, and stays off while google.tf has no client. The lifetimes are
# ZITADEL's defaults.
#
# Every organization inherits this login, blust.ch's included, and none sets one of its own: a
# login an organization sets in the console is a copy of this one at that moment and no longer
# follows it. Such a copy once kept external sign-in off on blust.ch after the instance turned it
# on, and hid the Google button wherever a sign-in names no organization.
resource "zitadel_default_login_policy" "this" {
  user_login                    = true
  allow_register                = false
  allow_external_idp            = local.google
  idps                          = zitadel_idp_google.google[*].id
  force_mfa                     = false
  force_mfa_local_only          = false
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
  second_factors                = []
  multi_factors                 = ["MULTI_FACTOR_TYPE_U2F_WITH_VERIFICATION"]
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

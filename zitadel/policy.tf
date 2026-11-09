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

# Whether anyone may open an account, which the comment on the login policy below says in full.
variable "open_sign_up" {
  type    = bool
  default = true
}

# Whether anyone may open an account is one switch, open_sign_up, on by default, which it may be
# only while the chat counts a reader without a role as a visitor and the privacy pages say that
# anyone may open an account; what an account may use is still a role the owner grants. Off, nobody
# registers: the owner makes each person with a verified address and no password, and the person
# signs in with Google, Microsoft or GitHub, which the link check links to that address once the
# provider has proved it (link-check.tf), and may add a passkey. On, anyone registers at the login
# with their address, and Google, Microsoft and GitHub open an account for a person who has none
# (google.tf, microsoft.tf, github.tf). Either way the login asks every account whose address is not
# verified for the code it mails there before the account is used, since ../infra runs it with
# EMAIL_VERIFICATION=true (checkEmailVerification in apps/login/src/lib/verify-helper.ts at ZITADEL
# v4.19.5).
#
# ZITADEL cannot allow passkeys and forbid passwords, since login v2 lets a passkey sign in only
# where local sign-in, which is passwords too, is on (apps/login/src/lib/server/loginname.ts at
# ZITADEL v4.19.5), so the setting allows both. With open_sign_up off the owner keeps the accounts
# passwordless: ZITADEL cannot remove a password, so an account that once had one has it replaced
# by a random one nobody keeps, and with no password to reset, the login's reset link stays
# hidden. With it on, the registration form lets a person choose a passkey or a password, and the
# reset link shows, since a person who chose a password needs a way back in; the reset goes to
# the verified address.
#
# Login v2 asks for any second factor a user holds after every sign-in but a passkey's, Google's
# included, whatever the settings force (checkMFAFactors in apps/login/src/lib/server/idp.ts at
# ZITADEL v4.19.5). With open_sign_up off, no second factor can be added, neither an authenticator
# app nor a security key, since one added once would stand in front of Google for good and no
# password needs it. With it on, a password sign-in needs one, force_mfa with force_mfa_local_only,
# and Google, Microsoft, GitHub and a passkey do not: the factor is an authenticator app or a
# security key, never a code by mail or text message, since the mailbox is already the reset channel
# and a code there adds nothing against a stolen mailbox, and its setup cannot be put off. A person
# who signed up with a password and an authenticator app and later links Google is then asked for
# the app after Google too, which is accepted; an account with no second factor is not asked.
# Google's own two steps guard a Google sign-in, Microsoft's own sign-in a Microsoft one, GitHub's
# own a GitHub one, which is a password alone for an account that has not turned on GitHub's
# two-factor authentication, the same trust the other two get, and a passkey is two factors by
# itself. External sign-in is allowed for Google, Microsoft and GitHub alone, each only once
# google.tf, microsoft.tf or github.tf names its client, and stays off while none does. The
# lifetimes are ZITADEL's defaults, but for the time a person may put off setting up a second
# factor, which is none with open_sign_up on.
#
# Every organization inherits this login, blust.ch's included, and none sets one of its own: a
# login an organization sets in the console is a copy of this one at that moment and no longer
# follows it. Such a copy once kept external sign-in off on blust.ch after the instance turned it
# on, and hid the Google button wherever a sign-in names no organization.
resource "zitadel_default_login_policy" "this" {
  user_login                    = true
  allow_register                = var.open_sign_up
  allow_external_idp            = local.google || local.microsoft || local.github
  idps                          = concat(zitadel_idp_google.google[*].id, zitadel_idp_azure_ad.microsoft[*].id, zitadel_idp_github.github[*].id)
  force_mfa                     = var.open_sign_up
  force_mfa_local_only          = var.open_sign_up
  passwordless_type             = "PASSWORDLESS_TYPE_ALLOWED"
  hide_password_reset           = !var.open_sign_up
  ignore_unknown_usernames      = true
  allow_domain_discovery        = false
  disable_login_with_email      = false
  disable_login_with_phone      = true
  default_redirect_uri          = "https://blust.ch/"
  password_check_lifetime       = "240h0m0s"
  external_login_check_lifetime = "240h0m0s"
  multi_factor_check_lifetime   = "12h0m0s"
  mfa_init_skip_lifetime        = var.open_sign_up ? "0s" : "720h0m0s"
  second_factor_check_lifetime  = "18h0m0s"
  second_factors                = var.open_sign_up ? ["SECOND_FACTOR_TYPE_OTP", "SECOND_FACTOR_TYPE_U2F"] : []
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

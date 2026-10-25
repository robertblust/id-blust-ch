# ZITADEL's mail: the invitation that lets a person the owner has made set up their sign-in, and
# the code that verifies an address. It goes out as digital-platform's does
# (robertblust/digital-platform, infra/zitadel/mail.tf): through Gmail's SMTP server, signed in
# as a Workspace user with an app password, because ZITADEL runs on Cloud Run without a fixed
# address, so no relay can allow it by IP, and Google's SMTP relay closes the connection on
# ZITADEL's greeting. The mail comes from no-reply@blust.ch, which the account sends as through
# Gmail's "Send mail as"; without that, Gmail puts the account's own address in its place.
#
# The account is a person's address, and this repository holds none, so it reaches the root from
# the repository secret ZITADEL_SMTP_USER, as the owner's login name reaches ../infra, and stays
# sensitive, out of the plans posted on pull requests. While it is empty ZITADEL sends no mail.
# The app password is in Secret Manager as zitadel-smtp-password, which ../infra makes empty and
# the owner fills, read for each run as an ephemeral value and given to ZITADEL as the provider's
# write-only password, so it reaches neither a file nor the state; the state keeps only the
# provider's one-way hash of it, to notice a rotation.
variable "smtp_user" {
  type      = string
  default   = null
  sensitive = true
  validation {
    condition     = var.smtp_user == null || var.smtp_user == "" || can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.smtp_user))
    error_message = "smtp_user is the Gmail account's address, from the secret ZITADEL_SMTP_USER, or empty."
  }
}

# A password given directly, which only the tests in tests/ do, for the reason google.tf gives for
# google_client_secret; CI never sets it.
variable "smtp_password" {
  type      = string
  default   = null
  sensitive = true
}

locals {
  # Whether mail is set up is no secret, though the address that decides it is.
  mail = nonsensitive(var.smtp_user != null && var.smtp_user != "")
}

ephemeral "google_secret_manager_secret_version" "smtp_password" {
  count  = local.mail && var.smtp_password == null ? 1 : 0
  secret = "zitadel-smtp-password"
}

resource "zitadel_email_provider_smtp" "gmail" {
  count            = local.mail ? 1 : 0
  description      = "Gmail"
  host             = "smtp.gmail.com:587"
  tls              = true
  user             = var.smtp_user
  password         = var.smtp_password != null ? var.smtp_password : ephemeral.google_secret_manager_secret_version.smtp_password[0].secret_data
  sender_address   = "no-reply@blust.ch"
  sender_name      = "blust.ch"
  reply_to_address = "no-reply@blust.ch"
  set_active       = true
}

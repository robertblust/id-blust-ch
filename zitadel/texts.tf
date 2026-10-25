# The words a reader meets at id.blust.ch, in English and Swiss Standard German, the two
# languages of the family's sites: the login's own pages, and the two mails ZITADEL sends once
# mail.tf has an account, the invitation and the code that verifies an address. They are the
# instance's defaults, for all three organizations, in the reader's language. The login lays its
# texts over its own, so only what is set here changes. Each text names the service as the
# address bar does, id.blust.ch, and says what a sign-in is for: choosing the model in the chats
# on blust.ch, companygraph.io and guestgraph.io. The chat's own words are the widget's
# (robertblust/design, assets/chat.js): "sign in", «anmelden», «Sie».
#
# ZITADEL names a mail's application with the invitation's, and falls back to "ZITADEL" when
# the invitation carries none, as the console's do, so the mails name the service in their
# texts, as digital-platform's do (robertblust/digital-platform, infra/zitadel/messages.tf). An
# invited person sets up Google or a passkey; the login offers a password too, since ZITADEL
# lets a passkey in only where passwords may (policy.tf), so the invitation names the two ways
# this service keeps.
resource "zitadel_default_hosted_login_translation" "en" {
  language = "en"
  translations = jsonencode({
    common = {
      title = "Sign in to id.blust.ch"
    }
    loginname = {
      title       = "Sign in"
      description = "Sign in to choose the model in the chats on blust.ch, companygraph.io and guestgraph.io."
      labels = {
        usernameOrEmail = "Email"
      }
    }
  })
}

resource "zitadel_default_hosted_login_translation" "de" {
  language = "de"
  translations = jsonencode({
    common = {
      title = "Bei id.blust.ch anmelden"
    }
    loginname = {
      title       = "Anmelden"
      description = "Melden Sie sich an, um in den Chats auf blust.ch, companygraph.io und guestgraph.io das Modell zu wählen."
      labels = {
        usernameOrEmail = "E-Mail"
      }
    }
  })
}

resource "zitadel_default_invite_user_message_text" "en" {
  language    = "en"
  title       = "Your invitation to id.blust.ch"
  pre_header  = "Your invitation to id.blust.ch"
  subject     = "Your invitation to id.blust.ch"
  greeting    = "Hello {{.DisplayName}},"
  text        = "You have been invited to id.blust.ch, the sign-in that lets you choose the model in the chats on blust.ch, companygraph.io and guestgraph.io. Click the button below to accept the invitation and set up your sign-in, with your Google account or a passkey. If you didn't expect this mail, please ignore it."
  button_text = "Accept the invitation"
}

resource "zitadel_default_invite_user_message_text" "de" {
  language    = "de"
  title       = "Ihre Einladung zu id.blust.ch"
  pre_header  = "Ihre Einladung zu id.blust.ch"
  subject     = "Ihre Einladung zu id.blust.ch"
  greeting    = "Guten Tag {{.DisplayName}}"
  text        = "Sie wurden zu id.blust.ch eingeladen, der Anmeldung, mit der Sie in den Chats auf blust.ch, companygraph.io und guestgraph.io das Modell wählen. Klicken Sie auf die Schaltfläche unten, um die Einladung anzunehmen und Ihre Anmeldung einzurichten, mit Ihrem Google-Konto oder einem Passkey. Wenn Sie diese E-Mail nicht erwartet haben, ignorieren Sie sie bitte."
  button_text = "Einladung annehmen"
}

resource "zitadel_default_verify_email_message_text" "en" {
  language    = "en"
  title       = "Confirm your email address"
  pre_header  = "Confirm your email address"
  subject     = "Confirm your email address for id.blust.ch"
  greeting    = "Hello {{.DisplayName}},"
  text        = "Please confirm this address for your sign-in at id.blust.ch with the button below, or enter the code {{.Code}}. If you didn't add this address, please ignore this mail."
  button_text = "Confirm the address"
}

resource "zitadel_default_verify_email_message_text" "de" {
  language    = "de"
  title       = "Bestätigen Sie Ihre E-Mail-Adresse"
  pre_header  = "Bestätigen Sie Ihre E-Mail-Adresse"
  subject     = "Bestätigen Sie Ihre E-Mail-Adresse für id.blust.ch"
  greeting    = "Guten Tag {{.DisplayName}}"
  text        = "Bitte bestätigen Sie diese Adresse für Ihre Anmeldung bei id.blust.ch mit der Schaltfläche unten, oder geben Sie den Code {{.Code}} ein. Wenn Sie diese Adresse nicht hinzugefügt haben, ignorieren Sie diese E-Mail bitte."
  button_text = "Adresse bestätigen"
}

# The words a reader meets at id.blust.ch, in English and Swiss Standard German, the two
# languages of the family's sites: the login's own pages, and the two mails ZITADEL sends once
# mail.tf has an account, the invitation and the code that verifies an address. They are the
# instance's defaults, for all three organizations, in the reader's language. Each text names the
# service as the address bar does, id.blust.ch, and says what a sign-in is for: choosing the model
# in the chats on blust.ch, companygraph.io and guestgraph.io.
#
# The German says du, not Sie: the owner chose it for id.blust.ch, against WRITING.md's rule
# that the reader is Sie, so the chat widget's «Melden Sie sich mit /login an» leads to a login
# that says «Melde dich an». The login lays the texts in texts/ over its own, which say Sie, so
# login-de.json gives a du form for every one of ZITADEL's German strings that addresses the
# reader (apps/login/locales/de.json at ZITADEL v4.19.5), the pages this instance never shows
# included, so no page mixes the two; a release that adds such a string shows it in Sie until it
# is added here. login-en.json changes only the title and the login-name page.
resource "zitadel_default_hosted_login_translation" "en" {
  language     = "en"
  translations = jsonencode(jsondecode(file("${path.module}/texts/login-en.json")))
}

resource "zitadel_default_hosted_login_translation" "de" {
  language     = "de"
  translations = jsonencode(jsondecode(file("${path.module}/texts/login-de.json")))
}

# ZITADEL names a mail's application with the invitation's, and falls back to "ZITADEL" when
# the invitation carries none, as the console's do, so the mails name the service in their
# texts, as digital-platform's do (robertblust/digital-platform, infra/zitadel/messages.tf). An
# invited person sets up Google or a passkey; the login offers a password too, since ZITADEL
# lets a passkey in only where passwords may (policy.tf), so the invitation names the two ways
# this service keeps.
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
  title       = "Deine Einladung zu id.blust.ch"
  pre_header  = "Deine Einladung zu id.blust.ch"
  subject     = "Deine Einladung zu id.blust.ch"
  greeting    = "Hallo {{.DisplayName}}"
  text        = "Du wurdest zu id.blust.ch eingeladen, der Anmeldung, mit der du in den Chats auf blust.ch, companygraph.io und guestgraph.io das Modell wählst. Klicke auf die Schaltfläche unten, um die Einladung anzunehmen und deine Anmeldung einzurichten, mit deinem Google-Konto oder einem Passkey. Wenn du diese E-Mail nicht erwartet hast, kannst du sie ignorieren."
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
  title       = "Bestätige deine E-Mail-Adresse"
  pre_header  = "Bestätige deine E-Mail-Adresse"
  subject     = "Bestätige deine E-Mail-Adresse für id.blust.ch"
  greeting    = "Hallo {{.DisplayName}}"
  text        = "Bitte bestätige diese Adresse für deine Anmeldung bei id.blust.ch mit der Schaltfläche unten, oder gib den Code {{.Code}} ein. Wenn du diese Adresse nicht hinzugefügt hast, kannst du diese E-Mail ignorieren."
  button_text = "Adresse bestätigen"
}

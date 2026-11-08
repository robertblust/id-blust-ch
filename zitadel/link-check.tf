# The link check, which makes every link by address on this instance, and why ZITADEL makes none.
# Login v2's own link by address searches for the user by the address alone and never asks whether
# that user's address was ever verified (handleAutoLinking in
# apps/login/src/lib/server/idp-intent.ts at ZITADEL v4.19.5, which searches with listUsers by
# email). Once anyone may open an account, that is a takeover in advance: a stranger opens an
# account on someone else's address and never enters its code, the real owner of the address later
# signs in with Google, login v2 links Google into the stranger's account, the real owner enters
# the code, since the mailbox is theirs, and from then on the stranger's password or Microsoft
# link opens the same account, with every role the owner later grants it. So google.tf and
# microsoft.tf set auto_linking to AUTO_LINKING_OPTION_UNSPECIFIED, and this service links
# instead. It does so whatever open_sign_up says, since it is what links an invited person's
# Google account too.
#
# ZITADEL calls it through an Actions v2 target of type REST_CALL with a response execution on
# RetrieveIdentityProviderIntent, the call the login makes after every sign-in with an external
# provider, the method and shape ZITADEL's guide "Test Actions Response Manipulation" uses. For a
# sign-in through Google or Microsoft whose answer names no linked user, the link check links when
# three things hold: the provider proved the address, by Google's own verified flag or by
# microsoft.tf's rules; exactly one account holds that address, compared without case; and that
# account's address is verified. It makes the link through ZITADEL's API
# (POST /v2/users/{userId}/links) and puts the account's id in the answer's userId, so the login
# signs the person in as an existing user (handleUserExists in the same file), and ZITADEL accepts
# that session only because the link now exists (CheckIntent in internal/command/session.go at
# ZITADEL v4.19.5 checks for an active link when the intent names no user). Otherwise it links
# nothing, and the person gets an account of their own, while open_sign_up is on, or the login's
# account-not-found page, or the login's error where ZITADEL refuses the address a second time;
# the owner sorts these out, and links the rest with link-idp.py, as the README's step 26 says.
# The endpoint's query names both providers' ids, an empty one for a provider that is not there,
# since the link check proves an address only for Microsoft's, applies only the three conditions
# for Google's and hands any other answer back unchanged.
#
# Every failure fails closed. interrupt_on_error is false and the timeout ten seconds, so a link
# check that is down or slow, or cannot reach ZITADEL or Microsoft, leaves the answer as it was: a
# link that exists still signs its person in, and nothing new is linked, since nothing else links
# by address. The payload is a JWT, which ZITADEL signs with the instance's own keys and the link
# check verifies against https://id.blust.ch/oauth/v2/keys, so no secret is shared. The provider
# still stores the target's generated signing_key in this root's state, whatever the payload; the
# JWT payload does not use it, so a reader of the state can forge nothing the link check accepts,
# and it is the one secret the state holds.
#
# The link check acts as the machine user link-check in blust.ch, where every account opened at
# the login lands, with ORG_USER_MANAGER there, the narrowest ZITADEL role that both reads users
# and adds links. Nothing here makes its key, a token or a secret: the owner makes the key by
# hand into zitadel-link-check-key, as the README's step 29 says, so it reaches neither the
# repository nor the state. blust.ch holds the owner's IAM_OWNER user and terraform, so that role
# reaches both, which makes the key as strong as the instance owner's, as
# ../infra/bootstrap/README.md says.
locals {
  link_check = local.google || local.microsoft
}

resource "zitadel_machine_user" "link_check" {
  count             = local.link_check ? 1 : 0
  org_id            = local.blust_ch
  user_name         = "link-check"
  name              = "Link check"
  description       = "Links a Google or Microsoft sign-in to the one account holding its proven address"
  access_token_type = "ACCESS_TOKEN_TYPE_BEARER"
}

resource "zitadel_org_member" "link_check" {
  count   = local.link_check ? 1 : 0
  org_id  = local.blust_ch
  user_id = zitadel_machine_user.link_check[0].id
  roles   = ["ORG_USER_MANAGER"]
}

resource "zitadel_action_target" "link_check" {
  count              = local.link_check ? 1 : 0
  name               = "link-check"
  endpoint           = "${local.issuer}/link-check/call?google=${one(zitadel_idp_google.google[*].id) == null ? "" : one(zitadel_idp_google.google[*].id)}&microsoft=${one(zitadel_idp_azure_ad.microsoft[*].id) == null ? "" : one(zitadel_idp_azure_ad.microsoft[*].id)}"
  target_type        = "REST_CALL"
  timeout            = "10s"
  interrupt_on_error = false
  payload_type       = "PAYLOAD_TYPE_JWT"
}

resource "zitadel_action_execution_response" "link_check" {
  count      = local.link_check ? 1 : 0
  method     = "/zitadel.user.v2.UserService/RetrieveIdentityProviderIntent"
  target_ids = [zitadel_action_target.link_check[0].id]
}

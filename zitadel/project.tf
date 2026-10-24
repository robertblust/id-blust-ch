# The grant model, and why it has a switch. A reader has one account, in their home organization,
# the owner's in blust.ch, and what they may use on a site is a role granted in that site's
# organization: the project chat lives in blust.ch and is granted to companygraph.io and
# guestgraph.io with all its roles, and an authorization made in companygraph.io names a user
# whose home is blust.ch. ZITADEL's documentation describes exactly that, a role assignment that
# "allows you to grant access to projects within your organization to users from other
# organizations" (https://zitadel.com/docs/concepts/features/external-user-grant, read Oct 22,
# 2026), and the token's roles claim then holds each role with the id of the organization it was
# granted in, which is how a chat server tells the sites apart. It is not yet confirmed on this
# instance, since it can be tried only once ZITADEL runs; the README's owner's steps say how.
#
# So the cross-organization model is the default: four roles, sonnet-5-5, opus, fable and haiku,
# and a site is the organization a role was granted in. If the owner's try shows that a site's
# organization cannot grant a role to a user of blust.ch, role_per_site = true builds the other
# model instead: a role per site and model, such as companygraph-io-opus, all granted in
# blust.ch with no project grant, and each site's chat.json then names its role_prefix, which the
# output sign_in carries. The chat server reads either model, and role_prefix says which.
variable "role_per_site" {
  type    = bool
  default = false
}

locals {
  models = {
    "sonnet-5-5" = "Sonnet 5.5"
    "opus"       = "Opus 5.5"
    "fable"      = "Fable 5.1"
    "haiku"      = "Haiku 5.5"
  }
  # The site's name as a role key may carry it, blust.ch as blust-ch.
  slug = { for site, s in local.sites : site => replace(site, ".", "-") }
  roles = var.role_per_site ? merge([
    for site, slug in local.slug : {
      for key, name in local.models : "${slug}-${key}" => { name = "${name} on ${site}", group = site }
    }
  ]...) : { for key, name in local.models : key => { name = name, group = null } }
}

# The roles reach the tokens, so the chat server reads them from the access token alone. A reader
# with no role on the project still signs in and gets the default model, so ZITADEL checks
# neither that the reader holds a role nor that their organization was granted the project.
resource "zitadel_project" "chat" {
  name                   = "chat"
  org_id                 = local.blust_ch
  project_role_assertion = true
  project_role_check     = false
  has_project_check      = false
}

resource "zitadel_project_role" "role" {
  for_each     = local.roles
  org_id       = local.blust_ch
  project_id   = zitadel_project.chat.id
  role_key     = each.key
  display_name = each.value.name
  group        = each.value.group
}

# Every role, to each site's organization but blust.ch's, which owns the project. With a role per
# site, every grant is made in blust.ch and no organization is granted the project.
resource "zitadel_project_grant" "site" {
  for_each       = var.role_per_site ? {} : zitadel_org.site
  org_id         = local.blust_ch
  project_id     = zitadel_project.chat.id
  granted_org_id = each.value.id
  role_keys      = keys(local.roles)
  depends_on     = [zitadel_project_role.role]
}

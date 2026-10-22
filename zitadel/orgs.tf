# blust.ch is the organization ZITADEL's first start made, with the owner as its first admin, so
# it is read rather than created; the owner's account lives there, and so does the project. Each
# other site gets an organization of its own, where its readers' grants are made.
data "zitadel_orgs" "blust_ch" {
  name        = "blust.ch"
  name_method = "TEXT_QUERY_METHOD_EQUALS"
  lifecycle {
    postcondition {
      condition     = length(self.ids) == 1
      error_message = "ZITADEL holds no single organization named blust.ch; ../infra's first start makes it."
    }
  }
}

resource "zitadel_org" "site" {
  for_each = { for site, s in local.sites : site => s if site != "blust.ch" }
  name     = each.key
}

locals {
  blust_ch = data.zitadel_orgs.blust_ch.ids[0]
  org_ids  = merge({ "blust.ch" = local.blust_ch }, { for site, o in zitadel_org.site : site => o.id })
}

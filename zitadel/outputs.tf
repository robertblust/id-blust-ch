# What each site's chat.json takes as its sign_in block, keyed by the site's origin: the issuer,
# the project the access token's audience holds, the organization whose grants count on that site
# and the site's client id. With a role per site, every grant is in blust.ch and the site is read
# from the role's name instead, so the block also names the prefix of the site's roles. The
# provider marks a client id sensitive, but a public client's id is no secret: every page that
# carries the chat names it in its script tag, so the output says it in the clear.
output "sign_in" {
  value = {
    for site, s in local.sites : s.origin => merge(
      {
        issuer     = local.issuer
        project_id = zitadel_project.chat.id
        org_id     = var.role_per_site ? local.blust_ch : local.org_ids[site]
        client_id  = nonsensitive(zitadel_application_oidc.site[site].client_id)
      },
      { for k, v in { role_prefix = "${local.slug[site]}-" } : k => v if var.role_per_site },
    )
  }
}

output "role_keys" {
  description = "The project's role keys, which the owner grants in the console"
  value       = sort(keys(local.roles))
}

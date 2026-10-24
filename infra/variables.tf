# ZITADEL's release, the same for the API and its login, which ZITADEL releases together and
# tests only together. Moved by hand, in a pull request that names the release, since Dependabot
# does not read an image tag inside Terraform.
variable "zitadel_version" {
  type    = string
  default = "v4.19.5"
}

# The owner's login name, an email address, which ZITADEL's first start makes the instance's
# first human admin in blust.ch. It reaches Terraform from the repository secret
# ZITADEL_ADMIN_LOGIN_NAME and never from a file, since an address belongs in no repository. It
# counts only on the first start; ZITADEL ignores it once the instance exists.
variable "admin_login_name" {
  type      = string
  sensitive = true
  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.admin_login_name))
    error_message = "admin_login_name is the owner's email address, from the secret ZITADEL_ADMIN_LOGIN_NAME."
  }
}

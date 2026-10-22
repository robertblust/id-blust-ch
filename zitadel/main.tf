# What ZITADEL holds, applied by CI on every push to main once ../infra runs it: the three
# organizations, the project chat and its roles, one application per site, and the instance's
# login and branding. People and the roles granted to them are not here: the owner invites a
# person and grants roles in ZITADEL's console, since an address belongs in no repository. State
# lives at the zitadel prefix of the bucket the bootstrap made.
terraform {
  required_version = ">= 1.10"
  required_providers {
    google  = { source = "hashicorp/google", version = "~> 8.0" }
    zitadel = { source = "zitadel/zitadel", version = "~> 3.8" }
  }
  backend "gcs" {
    bucket = "id-blust-ch-tfstate"
    prefix = "zitadel"
  }
}

locals {
  d      = jsondecode(file("${path.module}/../deployment.json"))
  sites  = { for s in jsondecode(file("${path.module}/../sites.json")) : s.site => s }
  issuer = "https://${local.d.domain}"
}

provider "google" {
  project = local.d.project
  region  = local.d.region
}

# The provider signs in as the machine user terraform, which holds the instance's IAM_OWNER role,
# with the JSON key the owner put into Secret Manager by hand. The key is read for each run as an
# ephemeral value, so it reaches the provider and never the state, the plan or a file.
ephemeral "google_secret_manager_secret_version" "admin_key" {
  secret = "zitadel-admin-key"
}

provider "zitadel" {
  domain           = local.d.domain
  port             = "443"
  insecure         = false
  jwt_profile_json = ephemeral.google_secret_manager_secret_version.admin_key.secret_data
}

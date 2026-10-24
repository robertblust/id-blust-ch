# What the bootstrap makes in blust-ch-mcp, the project it shares with the MCP host, applied to a
# mocked provider: no name meets one that mcp-blust-ch's bootstrap or roots make there, the
# identities' resource conditions name ZITADEL's secrets and instance, the state bucket's policy
# leaves out the project's viewers, and only this repository's pushes to main and pull requests
# reach the two identities. The provider checks the form of a
# member and an account's name, which a mock's random strings fail, so each account is given the
# values Google would give it.
mock_provider "google" {
  mock_resource "google_iam_workload_identity_pool" {
    defaults = { name = "projects/38003987140/locations/global/workloadIdentityPools/id-github" }
  }
}

override_resource {
  target = google_service_account.deploy
  values = {
    email  = "id-deploy@blust-ch-mcp.iam.gserviceaccount.com"
    member = "serviceAccount:id-deploy@blust-ch-mcp.iam.gserviceaccount.com"
    name   = "projects/blust-ch-mcp/serviceAccounts/id-deploy@blust-ch-mcp.iam.gserviceaccount.com"
  }
}

override_resource {
  target = google_service_account.plan
  values = {
    email  = "id-deploy-plan@blust-ch-mcp.iam.gserviceaccount.com"
    member = "serviceAccount:id-deploy-plan@blust-ch-mcp.iam.gserviceaccount.com"
    name   = "projects/blust-ch-mcp/serviceAccounts/id-deploy-plan@blust-ch-mcp.iam.gserviceaccount.com"
  }
}

override_resource {
  target = google_service_account.zitadel
  values = {
    email  = "zitadel@blust-ch-mcp.iam.gserviceaccount.com"
    member = "serviceAccount:zitadel@blust-ch-mcp.iam.gserviceaccount.com"
    name   = "projects/blust-ch-mcp/serviceAccounts/zitadel@blust-ch-mcp.iam.gserviceaccount.com"
  }
}

override_resource {
  target = google_service_account.login
  values = {
    email  = "zitadel-login@blust-ch-mcp.iam.gserviceaccount.com"
    member = "serviceAccount:zitadel-login@blust-ch-mcp.iam.gserviceaccount.com"
    name   = "projects/blust-ch-mcp/serviceAccounts/zitadel-login@blust-ch-mcp.iam.gserviceaccount.com"
  }
}

run "bootstrap" {
  command = apply

  assert {
    condition     = google_iam_workload_identity_pool.github.workload_identity_pool_id == "id-github"
    error_message = "The pool is id-github; github is the MCP host's."
  }
  assert {
    condition     = google_service_account.deploy.account_id == "id-deploy" && google_service_account.plan.account_id == "id-deploy-plan"
    error_message = "The CI identities are id-deploy and id-deploy-plan; deploy is the MCP host's image pusher."
  }
  assert {
    condition     = google_service_account.zitadel.account_id == "zitadel" && google_service_account.login.account_id == "zitadel-login"
    error_message = "The services' identities are the names ../ runs them as."
  }
  assert {
    condition     = google_storage_bucket.state.name == "id-blust-ch-tfstate"
    error_message = "The state bucket is the repository's; blust-ch-mcp-tfstate is the MCP host's."
  }
  assert {
    condition     = google_project_iam_member.deploy_secrets.condition[0].expression == "(resource.type != \"secretmanager.googleapis.com/Secret\" && resource.type != \"secretmanager.googleapis.com/SecretVersion\") || resource.name.startsWith(\"projects/38003987140/secrets/zitadel-\")" && google_project_iam_member.plan_secrets.condition[0].expression == "(resource.type != \"secretmanager.googleapis.com/Secret\" && resource.type != \"secretmanager.googleapis.com/SecretVersion\") || resource.name.startsWith(\"projects/38003987140/secrets/zitadel-\")"
    error_message = "Both identities' Secret Manager roles are held to secrets named zitadel-*, by the project's number, and pass the project, where making and listing are checked."
  }
  assert {
    condition     = google_project_iam_member.deploy_sql.condition[0].expression == "(resource.type != \"sqladmin.googleapis.com/Instance\" && resource.type != \"sqladmin.googleapis.com/BackupRun\") || resource.name == \"projects/blust-ch-mcp/instances/zitadel\" || resource.name.startsWith(\"projects/blust-ch-mcp/instances/zitadel/\")" && google_project_iam_member.plan_sql.condition[0].expression == "(resource.type != \"sqladmin.googleapis.com/Instance\" && resource.type != \"sqladmin.googleapis.com/BackupRun\") || resource.name == \"projects/blust-ch-mcp/instances/zitadel\" || resource.name.startsWith(\"projects/blust-ch-mcp/instances/zitadel/\")"
    error_message = "Both identities' Cloud SQL roles are held to the instance zitadel and its backups, by the project's id, and pass the project, where making and listing are checked."
  }
  assert {
    condition     = !contains(keys(google_project_iam_member.deploy), "roles/iam.serviceAccountUser") && !contains(keys(google_project_iam_member.deploy), "roles/iam.serviceAccountAdmin") && join(",", sort([for m in google_service_account_iam_member.deploy_runs_as : m.service_account_id])) == "projects/blust-ch-mcp/serviceAccounts/zitadel-login@blust-ch-mcp.iam.gserviceaccount.com,projects/blust-ch-mcp/serviceAccounts/zitadel@blust-ch-mcp.iam.gserviceaccount.com"
    error_message = "id-deploy acts as ZITADEL's two accounts alone, never as every account in the project."
  }
  assert {
    condition = jsondecode(google_storage_bucket_iam_policy.state.policy_data).bindings == [
      { role = "roles/storage.legacyBucketOwner", members = ["projectOwner:blust-ch-mcp"] },
      { role = "roles/storage.legacyObjectOwner", members = ["projectOwner:blust-ch-mcp"] },
      { role = "roles/storage.objectAdmin", members = ["serviceAccount:id-deploy@blust-ch-mcp.iam.gserviceaccount.com"] },
      { role = "roles/storage.objectViewer", members = ["serviceAccount:id-deploy-plan@blust-ch-mcp.iam.gserviceaccount.com"] },
    ]
    error_message = "The state bucket's policy is whole: the project's owners, id-deploy writing and id-deploy-plan reading, and not the project's viewers, which take in the MCP host's terraform-plan@."
  }
  assert {
    condition     = google_storage_bucket.state.uniform_bucket_level_access == true
    error_message = "The bucket's policy is the only access to its objects, with no object ACL beside it."
  }
  assert {
    condition     = !contains(keys(google_project_iam_member.plan), "roles/viewer")
    error_message = "id-deploy-plan holds no project viewer, which would read the MCP host's logs, meter and buckets."
  }
  assert {
    condition     = google_service_account_iam_member.deploy_wif.member == "principalSet://iam.googleapis.com/projects/38003987140/locations/global/workloadIdentityPools/id-github/attribute.event_ref/push:refs/heads/main" && google_service_account_iam_member.plan_wif.member == "principalSet://iam.googleapis.com/projects/38003987140/locations/global/workloadIdentityPools/id-github/attribute.event_name/pull_request"
    error_message = "Only a push to main applies and only a pull request plans, through this repository's pool."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.repository_id == \"1430227454\""
    error_message = "The provider accepts this repository's tokens alone, by its id."
  }
  assert {
    condition     = alltrue([for s in google_project_service.bootstrap : s.disable_on_destroy == false])
    error_message = "Destroying this root never turns off an API the MCP host uses."
  }
}

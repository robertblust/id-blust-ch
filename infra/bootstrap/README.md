# Bootstrap

What GitHub Actions needs before it can authenticate: the project `id-blust-ch` under the flatland.ch organization on the billing account `deployment.json` names, the APIs the other roots use, the state bucket `id-blust-ch-tfstate`, the identity pool and its GitHub provider, the `deploy` and `deploy-plan` service accounts and the monthly budget. Every value it takes is read from `../../deployment.json`.

The owner applies it, locally, under their own login, when the repository or the CI identities change. Creating the project needs the Project Creator role on the organization and the Billing Account User role on the billing account, and the budget needs the Billing Account Costs Manager role there; the owner holds all three, and CI's own accounts hold none. Its state is local and stays on the owner's machine, never in the bucket it creates, so a second copy of `terraform.tfstate` kept somewhere safe is the only backup it has. The state file is ignored by git and never committed.

Two values in `deployment.json` must be filled before the first apply, and the apply refuses to run until they are: `repository_id`, GitHub's numeric id for the repository, from `gh api repos/robertblust/id-blust-ch --jq .id`, and `budget_chf`, the owner's monthly figure in whole francs. The third, `project_number`, exists only once the project does; the apply prints it as the output `project_number`, and the owner writes it into `deployment.json` in the same pull request, since the workflows build the identity provider's name from it.

The first apply has no state to restore. Every later one restores it first: copy `~/id-blust-ch-bootstrap.tfstate` to `infra/bootstrap/terraform.tfstate` before running anything. The plan that follows must not add the project, the pool, the bucket or the service accounts — a plan that does means the state is missing rather than the infrastructure, so stop and find the copy before applying anything. Once the apply finishes, copy the state back out to the same file, and to the second safe copy.

    gcloud auth application-default login
    cp ~/id-blust-ch-bootstrap.tfstate infra/bootstrap/terraform.tfstate   # not on the first apply
    terraform -chdir=infra/bootstrap init
    terraform -chdir=infra/bootstrap plan
    terraform -chdir=infra/bootstrap apply
    cp infra/bootstrap/terraform.tfstate ~/id-blust-ch-bootstrap.tfstate
    terraform -chdir=infra/bootstrap output project_number

A run for a pull request plans as `deploy-plan@id-blust-ch.iam.gserviceaccount.com`, and only a push to `main` may apply, as `deploy@id-blust-ch.iam.gserviceaccount.com`; the bootstrap lets neither account be used the other way, and a run on `main` started by hand, on a schedule or by a comment gets neither. `deploy-plan@` changes nothing and reads the project's configuration, its IAM policies and the state, which holds no secret; the one secret value it reads is `zitadel-admin-key`, granted on that secret alone in `../secrets.tf`, because the `zitadel/` plan has to sign in to ZITADEL, and that key is the instance's IAM_OWNER. `deploy@` holds a Secret Manager role that makes secrets and sets their policies but reads no value, reads `zitadel-admin-key` by the same kind of grant, and holds the project IAM administrator role only for granting the Cloud SQL client role. `deploy@` still has two ways to any other secret's value: setting a secret's policy is setting who reads it, so it could grant itself one, and with the Cloud Run administrator and service account user roles it could deploy a revision that runs as `zitadel@` and reads that account's secrets. Every grant and service it makes is declared in `../` and recorded in the audit log, and only a push to `main` holds it.

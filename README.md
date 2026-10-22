# id.blust.ch

The family's own identity service, ZITADEL, at `https://id.blust.ch`. A reader signs in there once, on its hosted login, and the chats on blust.ch, companygraph.io and guestgraph.io then know who is asking and which models a grant lets them pick. The service runs in a Google Cloud project of its own in Zurich, `europe-west6`, and everything below the project is Terraform applied by GitHub Actions.

The repository is public and holds no person, address, key or token. People and the roles granted to them live in ZITADEL and are granted in its console, because an address belongs in no repository; every secret lives in Secret Manager and reaches a service or a workflow from there.

## Infrastructure

`infra/bootstrap/` is applied by the owner, with the state `infra/bootstrap/README.md` says how to keep, and makes what CI needs before it can authenticate: the project, its APIs, the state bucket, the identity pool and the two service accounts, and the monthly budget. A pull request plans as `deploy-plan@`, which reads and changes nothing, and only a run on `main` may apply, as `deploy@`. `deployment.json` holds this deployment's own values, and every root and workflow reads them from there.

## The owner's steps

Some steps need the owner's hands, because they create something outside this repository or need a role CI does not hold. They are done once, in this order.

1. Create the repository on GitHub as `robertblust/id-blust-ch`, public, push `main` to it, and add a ruleset on `main` that requires the status check `conventions / conventions` and a pull request.
2. Fill the two placeholders `deployment.json` holds before the bootstrap can run: `repository_id`, from `gh api repos/robertblust/id-blust-ch --jq .id`, and `budget_chf`, the monthly figure in whole francs.
3. Apply `infra/bootstrap/` as its README says, and write the `project_number` it prints into `deployment.json`. The three values reach `main` in one pull request.

## License

Apache-2.0, as `LICENSE` says.

<!-- conventions · v1.52.0 -->
Shared conventions of the robertblust, guestgraph and companygraph organizations live in `conventions/`, vendored from robertblust/conventions at the release `conventions.json` names. Read them before writing or committing anything here.

- `conventions/WRITING.md` — how we write: one voice, three registers, English and German.
- `conventions/WORKING.md` — how we work with git and GitHub.
- `conventions/REPOSITORIES.md` — the family: what each repository is and what pins what.
- `conventions/PINS.md` — what a member pins and how the family resync moves it.
- `conventions/WRITER.md`, `conventions/TRANSLATOR.md`, `conventions/EDITOR.md`,
  `conventions/BACKREADER.md`, `conventions/GLOSSARY.md`, `conventions/GERMAN.md` — the four roles
  that make a text, the terms they keep and the German they write.

Everything below this block is this repository's own. `sh conventions/conventions-sync check` says whether the copy matches the release, `sync` brings it to the release the pin names, and `sh conventions/conventions-check` holds this repository's own Markdown to `WRITING.md`, and `sh conventions/conventions-format` to its one form, which `fix` writes. Edit a shared file in robertblust/conventions, never here.
<!-- end conventions -->

## This repository

id.blust.ch: the family's own ZITADEL, the identity service a reader signs in at before a chat on blust.ch, companygraph.io or guestgraph.io lets them pick the model. It is public and holds no person, address, key or token: people and the roles granted to them live in ZITADEL and are granted in its console, and every secret lives in Secret Manager in the project `deployment.json` names. The required checks on `main` are `conventions / conventions` and `infra / terraform`, the job that plans `infra/` on a pull request and applies it on `main`.

`infra/bootstrap/` is the owner's, applied once by hand with local state, and makes what CI needs before it can authenticate: the project, its APIs, the state bucket, the CI identities and their identity pool, and the budget. `deployment.json` holds this deployment's own values, and every Terraform root and workflow reads them from there.

`infra/` is CI's, applied by `.github/workflows/infra.yml` on every push to `main`: the database, the secrets, ZITADEL and its login on Cloud Run, and the load balancer in front of them. `infra/domain.tf`'s first comment says why the front is a load balancer and not a domain mapping, with its sources. ZITADEL's release is `zitadel_version` in `infra/variables.tf`, one tag for the API and the login, moved by hand because no bot reads it.

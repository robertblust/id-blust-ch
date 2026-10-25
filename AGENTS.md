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

id.blust.ch: the family's own ZITADEL, the identity service a reader signs in at before a chat on blust.ch, companygraph.io or guestgraph.io lets them pick the model. It is public and holds no person, address, key or token: people and the roles granted to them live in ZITADEL and are granted in its console, and every secret lives in Secret Manager in the project `deployment.json` names. The required checks on `main` are `conventions / conventions`, `infra / terraform` and `zitadel / terraform`, the jobs that plan `infra/` and `zitadel/` on a pull request and apply them on `main`.

`infra/bootstrap/` is the owner's, applied once by hand with local state, and makes what CI needs before it can authenticate inside `blust-ch-mcp`, the project ZITADEL shares with the MCP host of `robertblust/mcp-blust-ch`: its APIs, the state bucket, the CI identities and their identity pool, and the services' accounts. The project, its budget and its organization policy are mcp-blust-ch's. A name that would meet one mcp-blust-ch makes there carries `id-`, and the CI identities' roles are held to secrets named `zitadel-*` and the instance `zitadel` by IAM conditions, so a new secret or instance keeps those names; `infra/bootstrap/README.md` says what each identity still reaches. `deployment.json` holds this deployment's own values, and every Terraform root and workflow reads them from there.

`infra/` is CI's, applied by `.github/workflows/infra.yml` on every push to `main`: the database, the secrets, ZITADEL and its login on Cloud Run, and the load balancer in front of them. `infra/domain.tf`'s first comment says why the front is a load balancer and not a domain mapping, with its sources. ZITADEL's release is `zitadel_version` in `infra/variables.tf`, one tag for the API and the login, moved by hand because no bot reads it; the login runs `login/Dockerfile`'s image of that release, whose build fails when a release moves the row it changes.

`zitadel/` is CI's too, applied by `.github/workflows/zitadel.yml` after `infra/`: the organizations, the project `chat` and its roles, one application per site in `sites.json`, and the instance's login and branding, with blust.ch's own login beside it, which forces a second factor. Set a login only here, never in the console: an organization's login made there is a copy that stops following the instance's. Its output `sign_in` is what each site's `chat.json` copies. `zitadel/project.tf`'s first comment holds the grant model and the switch `role_per_site`; a change to either is a change to what every chat server reads from a token.

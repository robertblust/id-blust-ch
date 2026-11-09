# Sign in with GitHub, as Google and Microsoft do

Design, 2026-11-09. Decided with Rob in conversation: GitHub behaves on id.blust.ch exactly as Google and Microsoft do, and is set up with Terraform as they are. What is marked *builder's call* is left to whoever builds it.

## Intent

Many of the readers the three chats are written for already hold a GitHub account and use it daily, and some of them hold neither a Google nor a Microsoft one they want to sign in with. A third button costs a reader nothing they do not choose, and it costs the service one more provider whose address must be proven before anything links on it, which the link check already does for the other two.

## Goals

- A GitHub button on the login of id.blust.ch, beside Google and Microsoft, once `github_client_id` names the owner's OAuth App.
- The same rules as the other two: linking allowed, an account opened only while `open_sign_up` is on and only after the person has seen the registration form, no automatic creation, no automatic update, no automatic linking.
- The link check links a GitHub sign-in to the one account holding its address only when GitHub proves the address is the person's, and that account's address is verified, as it does for Google and Microsoft.
- A new account opened with a GitHub address the link check did not prove gets the login's code before it is used.
- The client's secret reaches ZITADEL as Google's and Microsoft's do: from Secret Manager, as an ephemeral value, write-only, never in a file or the state.
- The invitation names GitHub while the login shows it. The README, the workflow's comments and the bootstrap README say the new secret and the owner's steps.

## Non-goals

- No GitHub Enterprise Server, and no GitHub App: an OAuth App on github.com, which is what ZITADEL's GitHub provider speaks.
- No restriction to members of an organization or to accounts with two-factor authentication on at GitHub. A role on the project `chat` is still what a reader may use, and only an admin grants one.
- The models' entries and the three privacy pages, which name every provider a reader may sign in with, change in their own pull requests after this one, as they did for Microsoft.

## Anti-goals

- A link from GitHub to an existing account on an address GitHub did not prove to be the person's.
- A new account that counts an address as verified when nothing proved it.
- A failure of the link check that stops a person from signing in with a link they already have, or that makes a link it should not.

## What ZITADEL's GitHub provider does (read, v4.19.5)

It takes the address from `GET https://api.github.com/user`, the profile's public email, and only where that is empty and the provider asks for `user:email` from `GET /user/emails`, the one address that is both primary and verified (`internal/idp/providers/github/session.go`, `FetchUser` and `getPrivateMail`). It then calls every address it took verified: `IsEmailVerified` returns `true` without reading anything (`internal/idp/providers/github/github.go`). The Terraform resource `zitadel_idp_github` has no switch to say otherwise. So the answer the link check receives says `isVerified: true` for every GitHub sign-in, whatever GitHub knows of the address.

The answer also carries GitHub's access token, in `idpInformation.oauth.accessToken`: ZITADEL keeps the tokens of a `*github.Session` (`internal/command/idp_intent.go`, `tokensForSucceededIDPIntent`) and returns the access token in the answer to `RetrieveIdentityProviderIntent` (`internal/api/grpc/user/v2/intent.go`, `idpOAuthTokensToPb`).

## How GitHub proves an address (decided)

The link check asks GitHub itself, per sign-in, with that access token: `GET https://api.github.com/user/emails`, which `user:email` allows. The address is proven when that list holds an entry equal to the answer's address, compared without case, whose `verified` is `true`. GitHub sends a code to every address added to an account and marks it verified only once the code is entered, so a verified entry is an address whose mailbox the account's holder reached.

- Proven: the link check proceeds as for Google and Microsoft. It links when exactly one account holds the address with it verified, and a new account keeps the address as verified, so it needs no code.
- Not proven, for any reason, an error or a timeout included: the link check links nothing, and it sets the answer's address to unverified, so a new account gets the login's code. This is the one thing it does for GitHub that it does for neither other provider, because ZITADEL's blanket `true` would otherwise skip the code. Login v2 makes the new account from the answer's email as the link check left it, its verification included (`resolveCreateUser` and `buildCreateUserRequest` in `apps/login/src/lib/server/idp-intent.ts` at v4.19.5), so an address set to unverified reaches the account that way.

## Scopes (decided)

`user:email` alone. `/user` answers without a scope for what ZITADEL reads of it, and `/user/emails` needs `user:email`. `read:user`, which ZITADEL's documentation suggests, would also let the token read the profile's private fields, which nothing here reads.

## The one gap that stays

The link check fails open by design: when it is down, or slower than the action's ten seconds, which a first call after it scaled to zero can be, ZITADEL keeps its own answer, so a link that exists still signs its person in. For GitHub that answer says the address is verified. So while the link check is down or too slow, a person who opens a new account through GitHub opens it without the login's code, on whichever address ZITADEL took. Nothing links on it, since ZITADEL itself links nothing. The address is either the primary verified one or the profile's public email, and GitHub's own documentation (read Nov 9, 2026) does not say whether a public email must be a verified address. **The owner checks that once before naming the client:** in GitHub's settings, under Public profile, whether the Public email field offers only verified addresses. If it does, every address ZITADEL takes from GitHub is one GitHub verified, and the gap is nil. If it does not, the gap is a stranger opening an account on someone else's address while the link check is down, which the next Google or Microsoft sign-in of the real owner could then link into. The fix then is to turn GitHub off while the link check is down, which this design does not build.

## What changes

- `zitadel/github.tf`: the variables `github_client_id`, null until the owner has made the OAuth App, and `github_client_secret` for the tests; the ephemeral read of `zitadel-github-client-secret`; `zitadel_idp_github` with the rules above.
- `zitadel/policy.tf`: GitHub among `idps` and in `allow_external_idp`.
- `zitadel/link-check.tf`: the endpoint names `github=` beside `google=` and `microsoft=`, and the link check exists while any of the three does.
- `zitadel/texts.tf`: the invitation names GitHub while the login shows it.
- `infra/secrets.tf`: `zitadel-github-client-secret` among the secrets the owner fills by hand, read by `id-deploy@` and `id-deploy-plan@` alone.
- `link-check/`: a GitHub client, a proof, the GitHub branch of `decide`, the `github` query parameter, and their tests.
- The tests of both Terraform roots, the README, the workflow's comments and `infra/bootstrap/README.md`.

## The owner's steps

Make an OAuth App on github.com under the owner's own settings, Developer settings, OAuth Apps, named `id.blust.ch`, with the homepage `https://id.blust.ch` and the callback `https://id.blust.ch/idps/callback`, login v2's, the same as Google's and Microsoft's. Put its client secret into `zitadel-github-client-secret` once this change is merged and `infra/` has applied. Check the public email, as above. Then set `github_client_id` in a pull request of its own, as for Google and Microsoft.

## Builder's calls

- The GitHub client's shape, timeout and headers, following `link-check/lib/graph.mjs`. GitHub's REST API refuses a request without a `User-Agent`, so the client names one that is generic and carries no address.
- Whether the GitHub proof sits in `prove.mjs` beside Microsoft's or in a file of its own.

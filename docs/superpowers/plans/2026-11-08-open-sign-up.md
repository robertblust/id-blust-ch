# Open sign-up on id.blust.ch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Anyone may open an account at id.blust.ch, by signing up or with Google or Microsoft. Links by address are made only on a proven address and only into an account whose address is verified. A signed-in reader without a role counts as a visitor in the chat.

**Architecture:** The chat server stops treating a role-less reader as a reader. A new small Node service in id-blust-ch, the **link check**, runs on Cloud Run behind id.blust.ch's load balancer. It is called by ZITADEL as an Actions v2 `REST_CALL` target on the response of `RetrieveIdentityProviderIntent`, proves Microsoft addresses through Graph, and makes every link by address itself through ZITADEL's API; ZITADEL's own link-by-address is off. Sign-up, creation, the forced second factor for passwords and the reset link turn on together behind one Terraform variable, last.

**Tech Stack:** Node ≥22 with no dependencies (`node:test`, `fetch`, `node:crypto`), Terraform with `zitadel/zitadel ~> 3.8` and `hashicorp/google`, GitHub Actions, ZITADEL v4.19.5 with login v2.

**Spec:** `docs/superpowers/specs/2026-11-08-open-sign-up-design.md` in this repository. Read it before any task; this plan argues from it.

## Global Constraints

- Rollout order, each part merged and live before the next starts: A (chat server), B (link check, sign-up off), C1 (privacy texts for B), then C2 (privacy texts for open accounts), then D (switch on). D also waits on all four chat deployments, mcp-azure-companygraph-io's included, running chat-server with Part A.
- Every repository works in a sibling worktree on its own branch, merges by pull request with `gh pr merge --merge`, never squash, and only on Rob's word.
- Agent commits are authored by the seat at the governing instance's domain, Rob is the committer, trailers `Process: Delivery`, `Phase: Implement`, `Track: Code` or `Track: Prose`, then `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Seats: Implementer for code, tests, re-pins and release bumps; Writer for English prose; Translator for German. Domains: id-blust-ch, robertblust/mental-model and robertblust.github.io `blust.ch`; chat-server, companygraph/mental-model and companygraph.github.io `companygraph.io`; guestgraph/mental-model and guestgraph.github.io `guestgraph.io`.
- Commit messages and every Markdown file follow `conventions/WRITING.md`; `sh conventions/conventions-check` and `sh conventions/conventions-format` pass in every repository touched.
- The repositories hold no person, address, key or token. The link check never logs a token or an address.
- id.blust.ch's own German says du; the sites' German says Sie.
- Values fixed by the spec: execution method `/zitadel.user.v2.UserService/RetrieveIdentityProviderIntent`; target `REST_CALL`, `PAYLOAD_TYPE_JWT`, `interrupt_on_error = false`, `timeout = "10s"`; `auto_linking = "AUTO_LINKING_OPTION_UNSPECIFIED"` on both providers; Microsoft `email_verified = false`; login env `EMAIL_VERIFICATION=true`; machine user `link-check` in blust.ch with `ORG_USER_MANAGER`; with sign-up on: `allow_register = true`, `force_mfa = true`, `force_mfa_local_only = true`, `second_factors = ["SECOND_FACTOR_TYPE_OTP", "SECOND_FACTOR_TYPE_U2F"]`, `mfa_init_skip_lifetime = "0s"`, `hide_password_reset = false`, `is_creation_allowed = true` on both providers, `is_auto_creation = false`.
- A personal Microsoft account's id matches `^[0-9a-f]{16}$`.

## Review Focus

- An address that differs only in case between the provider and ZITADEL (`Rob@Example.com` against `rob@example.com`) still links; every comparison ignores case. Test: `linksAcrossCase` in Task B1.
- Two accounts on one address, the owner's verified one and a stranger's unverified one, or two verified ones, never link; exactly one account must hold the address. Test: `twoAccountsNeverLink` in Task B1.
- A personal Microsoft account whose Graph `mail` is null and whose `userPrincipalName` is its address is proven; a work account whose `mail` is on a verified domain while its `userPrincipalName` is `…onmicrosoft.com` is proven by `mail`. Tests: `personalWithoutMail` and `workMailOnVerifiedDomain` in Task B1.
- A sign-in that is already linked (`userId` in the answer) passes through without a call to Graph or ZITADEL, so a slow Microsoft never slows a returning reader. Test: `alreadyLinkedTouchesNothing` in Task B1.
- ZITADEL rotates its web keys: a JWT signed with a key the link check hasn't fetched yet verifies after one refetch, and an unknown key after the refetch is refused. Test: `refetchesOnUnknownKid` in Task B3.

---

## Part A — the chat server (companygraph/chat-server)

Worktree `../chat-server-role-less-reader` on branch `role-less-reader-is-visitor` from `origin/main`.

### Task A1: A reader without a role counts as a visitor

**Files:**

- Modify: `lib/http.mjs` (the `if (r) reader = await gate.readers(...)` line, about line 262)
- Modify: `docs/INTERFACE.md` (the paragraph that says a reader's month is kept apart), `README.md` (the sentence on signed-in readers and the meter)
- Test: `test/http.test.mjs`

**Interfaces:**

- Consumes: `gate.verifier.reader(authorization)` returns `{ sub, models: Set<string> } | null`; `chosen(body, reader)`; `Meter.state()`.
- Produces: no new names.

- [ ] **Step 1: Write the failing tests** in `test/http.test.mjs`, beside `questionLineHasModelAndEffort`, using `signedIn()`, `verifier()`, `readerMeters()`, `bearer()`, `capturing()`, `Meter`, `MemoryStore`:
  - `roleLessReaderIsAVisitor`: `bearer({})`, a message with no model. Assert status 200, `keysAsked` is `[]`, `(await meter.state()).dayTokens > 0`, and `done`'s `by` is `{ model: "claude-sonnet-5", effort: "low" }`.
  - `roleElsewhereIsAVisitorHere`: `bearer({ opus: { "org-other": "other.test" } })`. Same assertions.
  - `roleLessReaderMayNotRaiseEffort`: `bearer({})` with `effort: "medium"`. Assert 403 `not_granted`, as for a visitor.
- [ ] **Step 2: Run** `node --test test/http.test.mjs`. Expected: the first two FAIL on `keysAsked`; the third passes already.
- [ ] **Step 3: Implement** in `lib/http.mjs`: a reader meter only when `r && r.models.size > 1`. The comment above it says why: a reader whose models on this site are the default alone is a visitor here.
- [ ] **Step 4: Run** `npm test`, `npm run typecheck`, `npm run build:check`. Expected: all pass, `questionLineHasModelAndEffort` included.
- [ ] **Step 5: Docs.** `docs/INTERFACE.md` and `README.md` say that a signed-in reader without a role on this site is answered and metered as a visitor, and that a reader's own month is a reader with a role's.
- [ ] **Step 6: Commit** as `Implementer <implementer@companygraph.io>`, `Track: Code`.

### Task A2: Release

**Files:** `package.json`, `package-lock.json`, the release notes the repository keeps.

- [ ] **Step 1:** Bump the version by the tooling spec's §2, decided by what a deployment must do about it. Nothing is required of a deployment, so it is not a major; expect `0.44.0`. The notes say what changed for a role-less reader.
- [ ] **Step 2:** `npm test`. Commit as Implementer, open the pull request, link it to this plan. Merge on Rob's word, then tag as the repository's release steps say.
- [ ] **Step 3:** Tell companygraph-fc that chat-server has a release for the family resync. The resync is owner-started and theirs. Part D waits until all four deployments run it.

---

## Part B — the link check (robertblust/id-blust-ch)

Worktree `../id-blust-ch-open-sign-up`, branch `open-sign-up`, which already holds the spec and this plan.

### Task B1: The decision

**Files:**

- Create: `link-check/package.json` (`"type": "module"`, `"engines": { "node": ">=22" }`, `"scripts": { "test": "node --test 'test/*.test.mjs'" }`, no dependencies)
- Create: `link-check/lib/decide.mjs`, `link-check/lib/prove.mjs`
- Test: `link-check/test/decide.test.mjs`, `link-check/test/prove.test.mjs`

**Interfaces:**

- Consumes: nothing.
- Produces:
  - `addressOf(answer: object): string | null`: `answer.createUser?.human?.email?.email ?? answer.addHumanUser?.email?.email ?? null`.
  - `markVerified(answer: object): object`: a copy whose `createUser.human.email` is `{ email, isVerified: true }`, dropping `sendCode` and `returnCode`, and whose `addHumanUser.email` is `{ email, isVerified: true }`, each only where present.
  - `provenByMicrosoft(accessToken: string, address: string, graph: Graph): Promise<"domain" | "personal" | null>`
  - `decide(answer: object, ids: { googleIdpId: string, microsoftIdpId: string }, deps: { graph: Graph, zitadel: Zitadel, log: (line: object) => void }): Promise<object>`. It never throws: on any error it logs `{ outcome: "error" }` and returns `answer` unchanged.
  - `Graph`: `{ me(token): Promise<{ id: string, mail: string | null, userPrincipalName: string }>, organization(token): Promise<{ ok: true, verifiedDomains: string[] } | { ok: false, status: number }> }`; `me` throws on any failure.
  - `Zitadel`: `{ usersByEmail(address): Promise<Array<{ userId: string, email: string, isVerified: boolean }>>, addLink(userId: string, link: { idpId: string, userId: string, userName: string }): Promise<void> }`.
  - Log lines: `{ idp: "google" | "microsoft" | "other", outcome: "already-linked" | "no-address" | "not-proven" | "no-account" | "ambiguous" | "unverified-account" | "linked" | "error", proof?: "domain" | "personal" }`, with no address and no token.

`provenByMicrosoft`, in order:

1. `me = await graph.me(token)`. On a throw, `null`.
2. The address must equal `me.mail` ignoring case, or `me.userPrincipalName` where `mail` is empty; otherwise `null`.
3. `org = await graph.organization(token)`. If `org.ok`, `"domain"` when the address's domain is one of `verifiedDomains` ignoring case, else `null`.
4. If `!org.ok` and `org.status` is 4xx and `me.id` matches `^[0-9a-f]{16}$`, `"personal"`; otherwise `null`.

`decide`, in order:

1. `idp` is `answer.idpInformation.idpId`; neither id gives `other`, unchanged.
2. `answer.userId` set gives `already-linked`, unchanged.
3. No address gives `no-address`, unchanged.
4. Proven: for Google, the address's own `isVerified` in `createUser` or `addHumanUser`; for Microsoft, `provenByMicrosoft(answer.idpInformation.oauth.accessToken, …)`, and a proven Microsoft answer becomes `markVerified(answer)`. Not proven gives `not-proven`, the answer as it is.
5. `users = (await zitadel.usersByEmail(address)).filter(u => same address ignoring case)`. None gives `no-account`; more than one, `ambiguous`; one with `isVerified` false, `unverified-account`. Each returns the answer of step 4.
6. `await zitadel.addLink(user.userId, { idpId, userId: answer.idpInformation.userId, userName: answer.idpInformation.userName })`, then return the answer with `userId: user.userId`, and log `linked`.

- [ ] **Step 1: Write the failing tests** with fakes for `Graph` and `Zitadel` that record their calls. For `provenByMicrosoft`:
  - `workAccountOnVerifiedDomain` gives `"domain"`.
  - `workMailOnVerifiedDomain`: `mail` on `example.com`, UPN on `x.onmicrosoft.com`, domains `["example.com", "x.onmicrosoft.com"]`, gives `"domain"`.
  - `workAccountForeignDomain` (`gmail.com` against `["example.com"]`) gives `null`.
  - `guestIsNotProven`: the address is the guest's own domain, absent from the tenant's list; `null`.
  - `personalWithoutMail`: `mail: null`, UPN is the address, `organization` returns `{ ok: false, status: 403 }`, id `3b78a729f3094e70`; `"personal"`.
  - `guidIdWithFailingOrganization` gives `null`.
  - `organization5xx` gives `null`.
  - `addressMismatch` gives `null`.
  - `meThrows` gives `null`.

  For `decide`:
  - `otherIdpUnchanged`.
  - `alreadyLinkedTouchesNothing`: deep equal, and zero calls on both fakes.
  - `googleVerifiedLinks`: `addLink` called once with the exact link, the answer's `userId` set.
  - `googleUnverifiedNotProven`: no lookup.
  - `microsoftProvenLinks`.
  - `microsoftProvenNewAccountMarkedVerified`: no account; the answer's `createUser.human.email` is `{ email, isVerified: true }` and `userId` unset.
  - `microsoftNotProvenLeftUnverified`.
  - `linksAcrossCase`.
  - `twoAccountsNeverLink`: no `addLink`.
  - `unverifiedAccountNeverLinks`: no `addLink`.
  - `lookupThrowsLinksNothing`: unchanged, logs `error`.
  - `addLinkThrowsLinksNothing`: `userId` unset, logs `error`.
  - `logsNoAddressOrToken`: no log line contains the address or the token string.
- [ ] **Step 2: Run** `cd link-check && npm test`. Expected: FAIL, modules missing.
- [ ] **Step 3: Implement** `link-check/lib/prove.mjs` and `link-check/lib/decide.mjs` to the interfaces above. Answers are copied, never mutated in place.
- [ ] **Step 4: Run** `npm test`. Expected: all pass.
- [ ] **Step 5: Commit** as `Implementer <implementer@blust.ch>`, `Track: Code`.

### Task B2: Graph and ZITADEL clients

**Files:**

- Create: `link-check/lib/graph.mjs`, `link-check/lib/zitadel.mjs`
- Test: `link-check/test/graph.test.mjs`, `link-check/test/zitadel.test.mjs`

**Interfaces:**

- Consumes: the `Graph` and `Zitadel` shapes from Task B1.
- Produces:
  - `graphClient({ fetch = globalThis.fetch, base = "https://graph.microsoft.com/v1.0", timeoutMs = 3000 } = {}): Graph`
    - `me` calls `GET {base}/me?$select=id,mail,userPrincipalName`.
    - `organization` calls `GET {base}/organization?$select=verifiedDomains` and reads `value[0].verifiedDomains[].name`.
    - Both send `Authorization: Bearer <token>` and abort at `timeoutMs`.
  - `zitadelClient({ issuer: string, key: { keyId: string, key: string, userId: string } | null, fetch = globalThis.fetch, now = () => Date.now() }): Zitadel`
    - Token: a JWT-bearer grant at `{issuer}/oauth/v2/token`, `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`, `scope=openid urn:zitadel:iam:org:project:id:zitadel:aud`. The assertion is RS256 over `{ iss: userId, sub: userId, aud: issuer, iat, exp: iat + 300 }` with header `{ alg: "RS256", kid: keyId }`, signed with `node:crypto`. The token is reused until 60 seconds before its `expires_in`.
    - `usersByEmail` posts `{issuer}/v2/users` with `{ queries: [{ emailQuery: { emailAddress, method: "TEXT_QUERY_METHOD_EQUALS_IGNORE_CASE" } }] }`, mapping `result[]` to `{ userId, email: human.email.email, isVerified: human.email.isVerified === true }`.
    - `addLink` posts `{issuer}/v2/users/{userId}/links` with `{ idpLink: { idpId, userId, userName } }`.
    - A null `key` makes both methods throw `"no key"`. A non-2xx status throws, carrying the status and never the body.

- [ ] **Step 1: Write the failing tests** with a fake `fetch` that records requests and answers canned bodies:
  - `meSelectsThreeFields`: URL, header.
  - `organizationReadsDomains`.
  - `organizationFailureIsStatus`: a 403 gives `{ ok: false, status: 403 }`.
  - `graphTimesOut`: a fetch that never resolves makes `me` reject within `timeoutMs`.
  - `tokenIsReused`: two calls, one token request.
  - `tokenRenewsNearExpiry`: `now` moved past `expires_in - 60` gives a second token request.
  - `assertionVerifies`: the assertion's signature verifies with the public half of a key generated in the test, and its claims are as above.
  - `usersByEmailQuery`: the exact body.
  - `addLinkBody`.
  - `nullKeyThrows`.
  - `errorCarriesNoBody`: the error message doesn't contain a canned secret-looking body.
- [ ] **Step 2: Run** `npm test`. Expected: FAIL.
- [ ] **Step 3: Implement** both clients.
- [ ] **Step 4: Run** `npm test`. Expected: all pass.
- [ ] **Step 5: Commit** as Implementer, `Track: Code`.

### Task B3: The service and its image

**Files:**

- Create: `link-check/lib/jwt.mjs`, `link-check/server.mjs`, `link-check/Dockerfile`, `link-check/.dockerignore` (`test/`)
- Test: `link-check/test/jwt.test.mjs`, `link-check/test/server.test.mjs`

**Interfaces:**

- Consumes: `decide`, `graphClient`, `zitadelClient`.
- Produces:
  - `jwtVerifier({ issuer: string, fetch = globalThis.fetch }): { verify(compact: string): Promise<object> }`. Keys come from `{issuer}/oauth/v2/keys`, cached, and fetched once more on an unknown `kid`. It accepts `RS256` and `ES256` (ES256 with `dsaEncoding: "ieee-p1363"`) and rejects every other `alg`. An `exp` present and past is refused.
  - `createServer({ verifier, decide, graph, zitadel, log }): http.Server`, exported from `server.mjs`.
    - `POST /link-check/call?google=<id>&microsoft=<id>`: the body is the compact JWT. A verified payload's `response` goes through `decide`, answered 200 `application/json` with the result. A verification failure answers 401 with no body; any other failure answers 500 with no body.
    - `GET /link-check/health` answers 200 `ok`; every other path 404.
  - Run as `node server.mjs` with env `ISSUER` and `LINK_CHECK_KEY`. `LINK_CHECK_KEY` that isn't valid key JSON, including the placeholder `{}`, gives `key: null`, logged once at start. `PORT` defaults to 8080.

- [ ] **Step 1: Write the failing tests:**
  - `verifiesRs256`.
  - `verifiesEs256`.
  - `refusesNone`: `alg: none` is refused.
  - `refusesForeignKey`: a token signed by a key not in the set.
  - `refetchesOnUnknownKid`: the first set lacks the kid, the second has it; verified, with exactly two key fetches.
  - `unknownKidAfterRefetchRefused`.
  - `refusesExpired`.
  - Server, over a real listening server with fakes:
    - `callRunsDecideWithQueryIds`: the ids from the query reach `decide`, and the 200 body is its result.
    - `badSignatureIs401`.
    - `decideThrowingIs500`.
    - `health`.
    - `otherPathIs404`.
- [ ] **Step 2: Run** `npm test`. Expected: FAIL.
- [ ] **Step 3: Implement.** The Dockerfile is `FROM node:22-alpine`, copies `package.json`, `server.mjs` and `lib/`, runs as `USER node`, with `CMD ["node", "server.mjs"]`, and labels `org.opencontainers.image.source=https://github.com/robertblust/id-blust-ch`.
- [ ] **Step 4: Run** `npm test`, then `docker build -t link-check-test link-check` and `docker run --rm -e ISSUER=https://id.blust.ch -e LINK_CHECK_KEY='{}' -p 8080:8080 link-check-test`, with `curl -fsS localhost:8080/link-check/health` in a second shell. Expected: tests pass, `ok`.
- [ ] **Step 5: Commit** as Implementer, `Track: Code`.

### Task B4: Infrastructure

**Files:**

- Modify: `infra/bootstrap/main.tf`: `google_service_account.link_check`, `account_id = "zitadel-link-check"`, and an entry `link_check` in `deploy_runs_as`. `infra/bootstrap/README.md` says what the account reaches.
- Modify: `infra/main.tf`: `link_check_email`, `link_check_member` beside `login_email`.
- Modify: `infra/secrets.tf`:
  - `zitadel-link-check-key` in `by_hand`, with a reader grant `"zitadel-link-check-key/link-check"` for `link_check_member` alone;
  - a placeholder version `{}`, made the way `login_token_placeholder` is, so the service can start before the owner's key exists.
- Modify: `infra/run.tf`:
  - `local.link_check_image = "ghcr.io/robertblust/id-blust-ch-link-check:${local.link_check_hash}"`, where `link_check_hash = substr(sha1(join("", [for f in sort(fileset("${path.module}/../link-check", "**")) : filesha256("${path.module}/../link-check/${f}")])), 0, 12)`;
  - `google_cloud_run_v2_service.link_check`: name `zitadel-link-check`, ingress `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER`, `invoker_iam_disabled = true`, scaling 0 to 2, cpu 1, memory 256Mi, `startup_cpu_boost`, port 8080, env `ISSUER = local.issuer`, `LINK_CHECK_KEY` from the secret at `latest`, `service_account = local.link_check_email`;
  - the login gains env `EMAIL_VERIFICATION = "true"`.
- Modify: `infra/domain.tf`: `run_services` gains `link_check`, and the path matcher a rule `["/link-check", "/link-check/*"]` to its backend.
- Modify: `.github/workflows/infra.yml`. Before Terraform, in the same job shape as the login image:
  - `npm test` in `link-check`;
  - the tag computed as `find link-check -type f | LC_ALL=C sort | while read -r f; do sha256sum "$f" | cut -c1-64; done | tr -d '\n' | sha1sum | cut -c1-12`;
  - build;
  - on a push, push unless the tag exists.
- Modify: `infra/tests/infra.tftest.hcl`. The secret count becomes 10. New asserts:
  - the link-check key is read by the link check's account alone and starts with only the placeholder;
  - the service runs as `zitadel-link-check@` and is reachable only through the load balancer;
  - the URL map sends `/link-check/*` to it;
  - the login carries `EMAIL_VERIFICATION = "true"`.
- Modify: `README.md`, the owner's steps:
  - **27** Apply `infra/bootstrap/` again for the new account, before merging this.
  - **28** After the first push builds `id-blust-ch-link-check`, make the package public, as step 18 does, and re-run the failed job.
  - **29** Make the link check's key, step 8's way. Make a personal access token for `link-check` that expires tomorrow, then `read -rs PAT && curl -fsS -X POST -H "Authorization: Bearer $PAT" -H 'content-type: application/json' -d '{"type":"KEY_TYPE_JSON","expirationDate":"<date>"}' https://id.blust.ch/management/v1/users/<link-check user id>/keys | jq -r .keyDetails | base64 --decode | gcloud secrets versions add zitadel-link-check-key --data-file=- --project blust-ch-mcp; unset PAT`, then delete the token. A link check started after that reads it; one already running keeps the placeholder until it scales to zero.
  - The paragraph on `infra/` names the new service, and the sentence that the state holds no secret names the target's unused `signing_key` (Task B5).

- [ ] **Step 1: Write the failing asserts** in `infra/tests/infra.tftest.hcl`. Run `terraform -chdir=infra test`. Expected: FAIL.
- [ ] **Step 2: Implement** the Terraform above. `terraform fmt -recursive`.
- [ ] **Step 3: Run** `terraform -chdir=infra test`, then `terraform -chdir=infra init -backend=false && terraform -chdir=infra validate`, and the same for `infra/bootstrap`. Expected: pass.
- [ ] **Step 4: Check the two hashes agree.** `terraform -chdir=infra console` with `local.link_check_hash` against the workflow's shell line run locally. Expected: identical.
- [ ] **Step 5: Write the README steps and comments**, then `sh conventions/conventions-check` and `sh conventions/conventions-format`.
- [ ] **Step 6: Commit** as Implementer, `Track: Code`.

### Task B5: ZITADEL: the target, the machine user, the links and the switch

**Files:**

- Create: `zitadel/link-check.tf`:
  - `local.link_check = local.google || local.microsoft`;
  - with `count = local.link_check ? 1 : 0`:
    - `zitadel_machine_user.link_check` (`org_id = local.blust_ch`, `user_name = "link-check"`, `name = "Link check"`);
    - `zitadel_org_member.link_check` (`roles = ["ORG_USER_MANAGER"]`);
    - `zitadel_action_target.link_check`: `name = "link-check"`, `endpoint = "${local.issuer}/link-check/call?google=${one(zitadel_idp_google.google[*].id) == null ? "" : one(zitadel_idp_google.google[*].id)}&microsoft=…"` the same way, `target_type = "REST_CALL"`, `timeout = "10s"`, `interrupt_on_error = false`, `payload_type = "PAYLOAD_TYPE_JWT"`;
    - `zitadel_action_execution_response.link_check` with `method = "/zitadel.user.v2.UserService/RetrieveIdentityProviderIntent"`.
  - Its comment says why the link check links and ZITADEL doesn't, with the spec's sources.
- Modify: `zitadel/policy.tf`: `variable "open_sign_up" { type = bool, default = false }`. The policy's values follow it: `allow_register`, `force_mfa`, `force_mfa_local_only`, `second_factors`, `mfa_init_skip_lifetime` (`"0s"` on, `"720h0m0s"` off), `hide_password_reset = !var.open_sign_up`. The comment is rewritten for both states.
- Modify: `zitadel/google.tf`: `auto_linking = "AUTO_LINKING_OPTION_UNSPECIFIED"`, `is_creation_allowed = var.open_sign_up`. The comment is rewritten: the link check links now.
- Modify: `zitadel/microsoft.tf`: `is_creation_allowed = var.open_sign_up`; the comment is rewritten.
- Modify: `zitadel/tests/zitadel.tftest.hcl`:
  - `mock_resource` for `zitadel_machine_user`, `zitadel_org_member`, `zitadel_action_target` and `zitadel_action_execution_response`;
  - new runs:
    - `sign_up_off` (the default): `allow_register == false`, `force_mfa == false`, `second_factors` empty, `hide_password_reset == true`, `is_creation_allowed == false` on both providers;
    - `sign_up_on`: the values from Global Constraints;
    - `link_check_with_google`: the target's type, payload, timeout and interrupt, the endpoint naming Google's id and an empty Microsoft one, the execution's method, `ORG_USER_MANAGER`;
    - `no_link_check_without_providers`: none of the four;
    - `google_does_not_auto_link`: `auto_linking == "AUTO_LINKING_OPTION_UNSPECIFIED"`.
  - The existing runs keep passing.
- Modify: `README.md`, the paragraph on `zitadel/`:
  - registration, the second factor and the reset link follow `open_sign_up`;
  - the link check makes every link by address;
  - step 17's "the login links the two" now says the link check does;
  - step 26 stays, for the cases the link check refuses.

- [ ] **Step 1: Write the failing runs.** Run `terraform -chdir=zitadel test`. Expected: the new runs FAIL.
- [ ] **Step 2: Implement.** `terraform fmt -recursive`.
- [ ] **Step 3: Run** `terraform -chdir=zitadel test` and `terraform -chdir=zitadel init -backend=false && terraform -chdir=zitadel validate`. Expected: all pass.
- [ ] **Step 4: README and comments**, then the conventions checks.
- [ ] **Step 5: Commit** as Implementer, `Track: Code`.
- [ ] **Step 6: Open the pull request for Part B** with Tasks B1–B5, its description linking the spec, this plan and the chat-server release. It merges only on Rob's word, after C1 has merged (Task C1), and after the owner's step 27. Steps 28 and 29 follow the merge.

### Task B6: Verify on the instance

No code. Run after Part B is live and steps 28 and 29 are done. Rob makes a test user in the console, with a verified address he controls and no Google or Microsoft link. Each check is recorded with what was seen.

- [ ] The link check's log shows calls for each Google or Microsoft sign-in, so the execution runs on the login's own call, the JWT verifies against `/oauth/v2/keys`, and the query ids arrive.
- [ ] The test user signs in with Google: the log shows `linked`, and the login signs them in as that user. The returned `userId` works.
- [ ] The test user signs in with a personal Microsoft account on the same address: `linked` with proof `personal`.
- [ ] A company Microsoft account on a verified domain: `linked` with proof `domain`. A company account whose address is on a domain the company doesn't hold: `not-proven`, and no link.
- [ ] `idpInformation.oauth.accessToken` was present, visible as a Graph call that succeeded.
- [ ] With the link check scaled to zero and its service stopped (`gcloud run services update zitadel-link-check --max-instances 0`, then back), Rob's own Google sign-in still works, and a fresh Google sign-in for a second verified test user does not link.
- [ ] Every existing human user's address is verified (`link-idp.py pending` lists them), so `EMAIL_VERIFICATION=true` asks nobody.

---

## Part C — the privacy texts

Each repository has its own worktree and pull request. The English is the Writer's, following `conventions/WRITER.md`. The German is the Translator's, following `conventions/TRANSLATOR.md` and `conventions/GERMAN.md`, with the editor's and back-reader's passes those files name. Each model's checks are whatever its `AGENTS.md` names. Each site runs the after-chain and the verify commands its `pins.json` names after its re-pin.

### Task C1: What Part B makes true

Merged before Part B, since B's merge makes it true.

**Files, in each of robertblust/mental-model, companygraph/mental-model and guestgraph/mental-model:**

- `model/systems/sign-in-with-microsoft.md`. The tagline's "never by the address" now reads: Microsoft links an existing account by its address when Microsoft proves it — a personal account's, or a company's own verified domain — and the account's address is verified.
- `model/systems/sign-in-with-google.md`: the same rule for Google, whose own verified flag proves the address.
- `model/data-processors/microsoft.md`: it is also asked which domains the reader's organization has verified, and that answer is used only to decide the link and is kept nowhere.
- `model/systems/id-blust-ch.md`: the link check, as part of id.blust.ch in Zurich.
- `model/processing-activities/signing-a-reader-in.md`: the link check's question to Microsoft, kept nowhere.

**Files, in each of the three sites:**

- `source.json`, re-pinned to the model's merge commit.
- `build/privacy.de.json`: a German row for every English row that changed.
- `privacy/index.html`: the sentence "An invited reader may also sign in with a Google account whose verified address is the invited one…" and its German name Microsoft, and the rule that a link needs a proven address and a verified account.

- [ ] **Step 1:** In each model: the Writer's English, the model's checks pass, commit as `Writer <writer@…>` with `Track: Prose`, open the pull request.
- [ ] **Step 2:** In each site: re-pin, the Translator's German rows and the paragraph's German, the after-chain and verify commands pass, commit the re-pin as Implementer and the German as `Translator <translator@…>`, open the pull request. A site's pull request merges after its model's.
- [ ] **Step 3:** After Rob's merges, check each live privacy page names Microsoft in the sign-in paragraph.

### Task C2: Accounts are open

Merged after Part B is verified (Task B6) and before Part D.

**Files, in each model:**

- `systems/id-blust-ch.md`: "by invitation only" becomes: anyone may open an account; what it may use is a role the owner gives.
- `processing-activities/signing-a-reader-in.md`: the purpose and the personal data cover readers the owner never invited.
- `data-processors/google.md`, `data-processors/microsoft.md`, `systems/sign-in-with-google.md`, `systems/sign-in-with-microsoft.md`: "a reader the owner has invited" goes.
- In companygraph's only: `data-objects/reader-account.md` (opened by anyone) and `bounded-contexts/answering/aggregates/meter.md` (a reader's month is a reader with a role's; one without a role counts with the visitors).
- Any other sentence `git grep -niE "invit|owner made|owner has made"` finds on the sign-in path.

**Files, in each site:**

- `source.json`, re-pinned.
- `build/privacy.de.json`.
- `privacy/index.html`:
  - "Nothing to fill in and nothing to sign up for. An account for the chat comes only by invitation" — the site itself still asks nothing, and an account is opened at id.blust.ch;
  - "An account is by invitation only";
  - "A reader I invite may sign in";
  - the sentence on what the chat keeps of a signed-in reader, now a reader with a role;
  - each with its German.
- `git grep -niE "invit|Einladung"` over each site, outside `docs/` and `node_modules/`, comes back empty or only with sentences that are still true.

- [ ] **Step 1:** Models, as in C1 Step 1.
- [ ] **Step 2:** Sites, as in C1 Step 2.
- [ ] **Step 3:** After Rob's merges, `curl -sL https://<site>/privacy | grep -ci "by invitation"` is 0 for all three.

---

## Part D — open the accounts (robertblust/id-blust-ch)

### Task D1: Switch on

**Files:**

- Modify: `zitadel/policy.tf`: `open_sign_up`'s default becomes `true`.
- Modify: `README.md`: the sign-up paragraph says accounts are open, and "Nobody signs in with a password" goes.

- [ ] **Step 1:** Change the default. `terraform -chdir=zitadel test` passes. The plan in the pull request shows exactly:
  - the login policy's six values;
  - `is_creation_allowed` on both providers;
  - nothing else.
- [ ] **Step 2:** Commit as Implementer, `Track: Code`, open the pull request. It merges on Rob's word only when all of these hold:
  - Part A runs on all four chat deployments;
  - Task B6 is complete;
  - Task C2 is live on the three sites.
- [ ] **Step 3: After the merge, on the instance:**
  - Sign up with a new address and a password. The login sends a code first, then forces an authenticator app or a security key with no skip, and the reset link shows.
  - Sign up with a passkey: no second factor is asked.
  - A new Google account on a fresh address: the registration form, then the account.
  - A company Microsoft account on an address its company hasn't verified opens an account and is asked for the code before it is used.
  - A role-less sign-in on blust.ch's chat: answered as a visitor, the day share counting.
  - Rob's own sign-ins with Google, Microsoft and a passkey are unchanged.

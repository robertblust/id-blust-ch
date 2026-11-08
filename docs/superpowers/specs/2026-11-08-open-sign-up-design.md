# Anyone may open an account; a role is what the owner gives

Design, 2026-11-08. Decided with Rob in conversation; what is marked *builder's call* is left to whoever builds it.

## Intent

Today id.blust.ch opens an account only when the owner invites someone, so every reader who wants to sign in waits on the owner first. Rob's view: a sign-in harms nothing. What a reader may use is a role on the project `chat`, and only an admin grants a role. So anyone may open an account, by signing up or with Google or Microsoft, and the owner's work shrinks to granting roles.

Two things must hold for that to be true, and both are part of this change:

1. An account without a role gets nothing a visitor doesn't already get. Today it does get more: a signed-in reader skips the visitors' day share and draws on a month of their own (`chat-server` `lib/http.mjs`, `lib/meter.mjs:129`), whether or not they hold a role.
2. Opening accounts must not open someone else's. Google and Microsoft link to an existing account by address, so the address has to be one the provider proved. Google's is proven as it is today. Microsoft's needs the link check below.

## Goals

- Sign-up is on: anyone may open an account at the login with their email address.
- Google and Microsoft may create an account when the person has none.
- Google and Microsoft link to an existing account by its address, but only when the address is proven to belong to the person signing in.
- A new account whose address is not proven gets the login's email code before it is used, as a sign-up does.
- In the chat, a signed-in reader without a role counts exactly as a visitor: the day share, the default model, the default effort. A role still unlocks other models, other efforts and the reader's own month.
- Every text that says accounts are by invitation says the new rule, in English and German: in the three models, on the three privacy pages, in id.blust.ch's own comments and README.

## Non-goals

- No way for a reader to ask for a role from inside the login or the chat; they ask the owner as today.
- No change to the roles, the grant model or `role_per_site`.
- No publisher verification in Entra; that stays as decided on 2026-11-07.
- No change to the invitation flow: the owner may still make an account and invite someone.

## Anti-goals

- A link from Microsoft to an existing account on an address Microsoft did not prove. This is the nOAuth attack: any company account can carry any address in Graph's `mail`, so such a link would let a stranger sign in as the owner with the owner's roles.
- An account without a role that gets more of the chat than a visitor.
- A failure of the link check that stops a reader from signing in with a link they already have, or that makes a link it should not.

## How Microsoft proves an address (decided)

ZITADEL's Microsoft provider has one switch for addresses, all verified or none (`internal/idp/providers/azuread/azuread.go` at v4.19.5: "AzureAD does not return an `email_verified` claim"). With the common tenant it also drops Microsoft's ID token (`azuread/session.go`, `FetchUser` returns before it keeps the token), so the `xms_edov` claim never arrives. The access token does arrive, in the answer to `RetrieveIdentityProviderIntent` (`idpInformation.oauth.accessToken`), and it carries the `User.Read` permission the provider already asks for.

So the provider stays at `email_verified = false`, and a small service of ours, the **link check**, decides per sign-in:

- **A work or school account.** `GET https://graph.microsoft.com/v1.0/organization?$select=verifiedDomains` answers with the domains the person's own company has proven it owns; with `User.Read` it returns exactly `id`, `displayName` and `verifiedDomains` (Microsoft Graph, "Get organization", read 2026-11-08). The address is proven when its domain, compared without case, is one of those names. A guest in someone else's company is asked about that company's domains, so a guest's own address is not proven, which is the safe answer.
- **A personal Microsoft account.** `GET /organization` is not supported for personal accounts and fails. The address is proven when that call fails *and* `GET /me` answers with an `id` of 16 hexadecimal characters, the form of a personal account's id, where a company account's is a GUID. Microsoft verified a personal account's address when it was made.
- **Anything else** (a call that fails another way, an answer of another shape, a timeout): not proven.

The address checked is the one ZITADEL will use, `userAction.createUser.human.email.email` and the deprecated `addHumanUser.email.email`. The check also requires it to equal, without case, Graph's `mail` or, where `mail` is empty, `userPrincipalName`, since that is where ZITADEL took it from; a mismatch is not proven.

A proven address is what the link check links on, under the rule in the next section. When the address is proven and no account is linked, it also marks the address verified in both fields, so a new account opened with it needs no code. An unproven address is left unverified, so its new account gets the code.

## Never link into an unverified account (decided)

Open accounts allow a takeover in advance. A stranger opens an account on someone else's address, through the sign-up form or with a company Microsoft account that carries the address unproven, and never enters the code. Later the real owner of the address signs in with Google or with a proven Microsoft address. Login v2 links by address without asking whether the found account's address was ever verified (`handleAutoLinking` searches with `listUsers` by email alone). The real owner then enters the code, since it's their mailbox, and from then on the stranger's password or Microsoft link opens the same account, with every role the owner later grants it. Requiring verification alone doesn't stop this, because the real owner's own code is what unlocks the stranger's way in.

So two rules hold together:

- **Every account verifies its address before it is used.** The login runs with `EMAIL_VERIFICATION=true` (`checkEmailVerification` in `apps/login/src/lib/verify-helper.ts` at v4.19.5), set on the login's Cloud Run service in `infra/run.tf`.
- **Nothing links by address into an account whose address isn't verified.** ZITADEL's own link-by-address is off for both providers (`auto_linking = "AUTO_LINKING_OPTION_UNSPECIFIED"`), and the link check makes every link by address itself. For a sign-in through Google or Microsoft whose answer names no linked user, it links when three things hold: the provider proved the address (Google's own verified flag; Microsoft's by the rules above), exactly one account holds that address, and that account's address is verified. It makes the link through ZITADEL's API (`POST /v2/users/{userId}/links`) and puts the account's id in the answer's `userId`. The login then signs the person in as an existing user (`handleUserExists` in `idp-intent.ts`), and ZITADEL accepts the session only because the link now exists (`CheckIntent` in `internal/command/session.go` at v4.19.5 checks for an active link when the intent names no user). Otherwise it links nothing, and the person signing in gets an account of their own, or the login's error where ZITADEL refuses the address twice, and the owner sorts that out. The stranger's account stays unusable for good.

Because the link check is the only thing that links by address, every failure fails closed: when the link check is down, slow or can't reach ZITADEL or Microsoft, nothing is linked, and a sign-in with a link that already exists goes on as before. It needs a ZITADEL machine account that reads the users of blust.ch and adds links to them, with its key in Secret Manager as `zitadel-admin-key` is kept, read by the link check at run time.

*My call:* the machine account is `link-check` in blust.ch with the role `ORG_USER_MANAGER` there, the narrowest ZITADEL role that both reads users and adds links. That is a strong right, and the link check holds it alone; the owner makes its key by hand, as step 8 of the README makes `terraform`'s, so the key reaches neither the repository nor the state.

## How the link check runs (decided)

- A ZITADEL Actions v2 target of type `REST_CALL`, with a response execution on `/zitadel.user.v2.UserService/RetrieveIdentityProviderIntent`. ZITADEL's guide "Test Actions Response Manipulation" uses exactly this method and shows the shape of what is sent and returned. Terraform: `zitadel_action_target` and `zitadel_action_execution_response`, both in provider 3.8.7.
- `payload_type = "PAYLOAD_TYPE_JWT"`: ZITADEL signs each call with the instance's own keys, and the link check verifies the signature against `https://id.blust.ch`'s published keys. There's no shared secret to keep. It answers nothing to a call it can't verify.
- `interrupt_on_error = false` and a timeout of 10 seconds, so when the link check is down a sign-in goes on with the answer unchanged: existing links work, and nothing is linked, since ZITADEL's own link-by-address is off.
- It proves addresses only when `idpInformation.idpId` is the Microsoft provider's id, which Terraform hands it. For Google it only applies the guard above. For any other provider it returns the answer unchanged.
- It keeps nothing. It never logs a token or an address, only the provider, the outcome (proven by domain, proven as a personal account, not proven) and errors.
- It runs on Cloud Run in `blust-ch-mcp`, in the Zurich region like ZITADEL, built and deployed by `infra/` the way the login image is.

*Builder's call:* the language (the family's services are Node; Node's own `fetch` and `crypto` are enough), where it sits (behind the load balancer on a path ZITADEL doesn't use, or on its own Cloud Run address), its timeout, and the name of the service and the image.

## The login (decided)

- `zitadel_default_login_policy`: `allow_register = true`. The sign-up form lets a person choose a passkey or a password, since ZITADEL can't allow passkeys and forbid passwords (`policy.tf`'s comment), and Rob accepts passwords.
- **A password sign-in needs a second factor; Google, Microsoft and a passkey don't (decided).** `force_mfa = true` with `force_mfa_local_only = true`. A passkey is two factors by itself. For the second factor to exist, `second_factors` gains an authenticator app (`SECOND_FACTOR_TYPE_OTP`) and a security key (`SECOND_FACTOR_TYPE_U2F`). *My call:* no code by email or text message as a second factor, since the mailbox is already the reset channel and a code there adds nothing against a stolen mailbox. `mfa_init_skip_lifetime` goes to zero so the setup can't be postponed.
- **Passwords can be reset.** `hide_password_reset = false`, since a person who chose a password needs a way back in. The reset goes to the verified address.
- `policy.tf`'s comment says why login v2 asks for a second factor a user holds after every sign-in but a passkey's, Google's included (`checkMFAFactors` in `apps/login/src/lib/server/idp.ts` at v4.19.5). That stays true and is accepted: someone who signed up with a password and an authenticator app, and later links Google, is asked for the app after Google too. Accounts with no second factor, all of today's, are unaffected. The comment is rewritten for the new rules.
- `zitadel_idp_google`: `is_creation_allowed = true`; `auto_linking = "AUTO_LINKING_OPTION_UNSPECIFIED"`, since the link check links instead.
- `zitadel_idp_azure_ad`: `is_creation_allowed = true`; `auto_linking` stays `AUTO_LINKING_OPTION_UNSPECIFIED`; `email_verified` stays `false`, which is what makes the link check the only way an address becomes proven.
- A new account lands in the default organization, blust.ch, as an invited one does; the owner grants roles in a site's organization as today.
- Sign-up and creation turn on behind one variable, off by default, switched on in the last step of the rollout below. The link check, and with it linking by address for both providers, is not behind it: it goes live in step 2. `link-idp.py` stays for the cases the check refuses.
- *My call:* the provider stores the target's generated `signing_key` in the `zitadel/` state, whatever the payload type. The JWT payload doesn't use it, so a reader of the state can forge nothing the link check accepts. The README's sentence that the state holds no secret is amended to name it. If the JWT doesn't verify against the instance's published keys on the instance, the design comes back to the owner; it does not fall back to that key on its own.

*Builder's call:* `is_auto_creation` (my call: `false`, so the person sees the registration form before an account is made); the login's texts where they still speak of invitations; how the README's owner's steps change.

## The chat server (decided)

A signed-in reader whose models on this site are the default model alone is handled exactly as a visitor: no reader meter, the day share, `DEFAULT_CHOICE`. *My call:* "without a role" is read per site, the same test `chosen()` in `lib/shape.mjs` already makes (`reader.models.size === 1`). A reader granted `opus` on companygraph.io therefore counts as a visitor on blust.ch, since nothing there is theirs beyond the default. Everything else about sign-in stays. The interface document and the README say so. *Builder's call:* the release number, by the tooling spec's §2.

## Privacy (decided in substance)

The rule every text must now state: anyone may open an account; what it may use is a role the owner gives. Plus what is new:

- The account data of people the owner never invited: name, address, the links to Google or Microsoft.
- The link check: for a Microsoft sign-in, id.blust.ch asks Microsoft for the verified domains of the person's organization, keeps nothing and uses the answer only to decide whether the address is proven.
- Microsoft may now link an existing account, where the privacy texts of 2026-11-07 say it never does.

Where the texts are, at least: in each of the three models, `processing-activities/signing-a-reader-in.md`, `systems/id-blust-ch.md`, `systems/sign-in-with-google.md`, `systems/sign-in-with-microsoft.md`, `data-processors/google.md`, `data-processors/microsoft.md`; in companygraph's, `data-objects/reader-account.md` and `bounded-contexts/answering/aggregates/meter.md` too. Each site's privacy page has a sign-in paragraph that says "An account for the chat comes only by invitation" and "An account is by invitation only" with their German, and still names only Google; it gains the new rule and Microsoft. Its German goes in `build/privacy.de.json`. *Builder's call:* finding every other sentence, by searching for invitation and Einladung across the models, the sites and this repository.

## Rollout order (decided)

1. The chat server: a reader without a role counts as a visitor. Release, then the family resync to the deployments.
2. id.blust.ch: Microsoft links an existing account by a proven address. This is the link check with its target and execution; it takes over Google's linking by address too, with the guard. Nothing opens an account yet: sign-up and creation stay off. Verified on the instance with a personal and a company Microsoft account against a test user.
   *My call:* the privacy sentences step 2 makes true go out in the same round, merged before step 2 goes live: that Microsoft now links an existing account on a proven address, and the link check's question to Microsoft.
3. The models and the sites: the new privacy texts about open accounts, in English and German.
4. id.blust.ch: the variable switched on. This is the step that opens accounts, and it comes only after steps 1–3 are merged and live.

## To verify on the instance before step 4

These are what the design relies on and haven't been seen on id.blust.ch yet:

- That the response execution runs on the login's own call to `RetrieveIdentityProviderIntent` and that the login reads the changed answer.
- That a `REST_CALL` target with a JWT payload has its answer accepted as plain JSON.
- That `idpInformation.oauth.accessToken` is present for a Microsoft sign-in through the common tenant.
- That a personal account's `userPrincipalName` from Graph is its sign-in address, and that its `/organization` call fails.
- That a new account with an unverified address gets the login's email code before it is used.
- That a JWT payload verifies against the keys at `https://id.blust.ch/oauth/v2/keys`.
- That with `force_mfa_local_only`, a password sign-in without a second factor is sent to set one up and can't skip it, and that Google, Microsoft and passkey sign-ins aren't asked.
- That `EMAIL_VERIFICATION=true` asks for the code after every kind of sign-in (password, passkey, Google, Microsoft) on an account whose address isn't verified, and that invited accounts and the owner's are already verified.
- That an answer whose `userId` the link check filled, after making the link, signs the person in as that account.

## Tests

- The link check, against canned Graph answers: a company account on a verified domain (proven), on a domain the company doesn't hold (not proven), a guest (not proven), a personal account (proven), `/organization` failing for an id that is a GUID (not proven), Graph down or slow (unchanged), a Google sign-in (unchanged), an address that doesn't match `mail` or `userPrincipalName` (not proven), a call with a bad or missing signature (refused), and for the guard: a Google or proven Microsoft address on an account whose address is verified (link), on one whose address isn't (no link), with no account (unchanged), and the lookup failing (no link).
- `terraform test` in `zitadel/`: with the variable off, sign-up, creation, the forced second factor and the reset link stay as today. With it on, sign-up and creation open on both providers, a password needs a second factor and the reset link shows. The target and the execution exist whenever Google or Microsoft is configured, whatever the variable says.
- The chat server: a signed-in reader without a role is metered against the day share and gets no reader meter; one with a role is as today.

## Known risks, accepted

- Mail: ZITADEL sends through a Gmail account (`zitadel/mail.tf`), which caps how many mails go out a day. A wave of sign-ups, real or not, can use up a day's mails, and then invitations and codes wait for the next day.
- An account someone opens and never uses stays until the owner deletes it.
- A person the owner invited earlier who signs in with Microsoft on an address Microsoft didn't prove gets a second account or an error, never theirs. The owner links them with `link-idp.py`.

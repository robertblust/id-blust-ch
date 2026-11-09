import { test } from "node:test";
import assert from "node:assert/strict";
import { decide, addressOf, markVerified, markUnverified } from "../lib/decide.mjs";

const ids = { googleIdpId: "g-1", microsoftIdpId: "m-1", githubIdpId: "gh-1" };
const TOKEN = "tok-secret-123";
const PERSONAL_ID = "3b78a729f3094e70";

function answerFor(idpId, address, { verified = false, userId, token = TOKEN } = {}) {
  const email = verified ? { email: address, isVerified: true } : { email: address, sendCode: {} };
  const answer = {
    details: { sequence: "1" },
    idpInformation: {
      idpId,
      userId: "ext-42",
      userName: "External Name",
      oauth: { accessToken: token },
      rawInformation: {},
    },
    createUser: { username: address, human: { profile: { givenName: "A" }, email } },
    addHumanUser: { username: address, profile: { givenName: "A" }, email: { ...email } },
  };
  if (userId) answer.userId = userId;
  return answer;
}

function fakes({ users = [], lookupThrows = false, addLinkThrows = false, me, org, emails, githubThrows = false } = {}) {
  const log = [];
  const zitadelCalls = [];
  const graphCalls = [];
  const githubCalls = [];
  return {
    log,
    zitadelCalls,
    graphCalls,
    githubCalls,
    deps: {
      log: (line) => log.push(line),
      github: {
        async emails(token) {
          githubCalls.push(["emails", token]);
          if (githubThrows || !emails) throw new Error("github down");
          return emails;
        },
      },
      graph: {
        async me(token) {
          graphCalls.push(["me", token]);
          if (!me) throw new Error("no me");
          return me;
        },
        async organization(token) {
          graphCalls.push(["organization", token]);
          return org ?? { ok: false, status: 403 };
        },
      },
      zitadel: {
        async usersByEmail(address) {
          zitadelCalls.push(["usersByEmail", address]);
          if (lookupThrows) throw new Error("zitadel down");
          return users;
        },
        async addLink(userId, link) {
          zitadelCalls.push(["addLink", userId, link]);
          if (addLinkThrows) throw new Error("zitadel down");
        },
      },
    },
  };
}

const addLinks = (f) => f.zitadelCalls.filter((c) => c[0] === "addLink");
const workMe = (address) => ({ id: "6f1c2a9e-0b7d-4c55-9a3e-1d2f3a4b5c6d", mail: address, userPrincipalName: address });
const workOrg = { ok: true, verifiedDomains: ["example.com"] };

test("addressOf and markVerified", () => {
  const a = answerFor("g-1", "a@b.c");
  assert.equal(addressOf(a), "a@b.c");
  assert.equal(addressOf({ addHumanUser: { email: { email: "x@y.z" } } }), "x@y.z");
  assert.equal(addressOf({}), null);
  const before = structuredClone(a);
  const m = markVerified(a);
  assert.deepEqual(a, before);
  assert.deepEqual(m.createUser.human.email, { email: "a@b.c", isVerified: true });
  assert.deepEqual(m.addHumanUser.email, { email: "a@b.c", isVerified: true });
  assert.deepEqual(markVerified({ idpInformation: {} }), { idpInformation: {} });
  const n = markVerified(a, "n@o.p");
  assert.deepEqual(n.createUser.human.email, { email: "n@o.p", isVerified: true });
  assert.deepEqual(n.addHumanUser.email, { email: "n@o.p", isVerified: true });
});

test("otherIdpUnchanged", async () => {
  const f = fakes();
  const a = answerFor("other-idp", "a@example.com", { verified: true });
  const before = structuredClone(a);
  assert.deepEqual(await decide(a, ids, f.deps), before);
  assert.deepEqual(f.log, []);
  assert.equal(f.zitadelCalls.length + f.graphCalls.length, 0);
});

test("alreadyLinkedTouchesNothing", async () => {
  for (const idpId of ["g-1", "m-1"]) {
    const f = fakes();
    const a = answerFor(idpId, "a@example.com", { userId: "u-9" });
    const before = structuredClone(a);
    assert.deepEqual(await decide(a, ids, f.deps), before);
    assert.equal(f.zitadelCalls.length, 0);
    assert.equal(f.graphCalls.length, 0);
    assert.equal(f.log[0].outcome, "already-linked");
  }
});

test("googleVerifiedLinks", async () => {
  const f = fakes({ users: [{ userId: "u-1", email: "a@example.com", isVerified: true }] });
  const a = answerFor("g-1", "a@example.com", { verified: true });
  const out = await decide(a, ids, f.deps);
  assert.equal(out.userId, "u-1");
  assert.equal(addLinks(f).length, 1);
  assert.deepEqual(addLinks(f)[0], ["addLink", "u-1", { idpId: "g-1", userId: "ext-42", userName: "External Name" }]);
  assert.equal(a.userId, undefined);
  assert.deepEqual(f.log, [{ idp: "google", outcome: "linked" }]);
  assert.equal(f.graphCalls.length, 0);
});

test("googleUnverifiedNotProven", async () => {
  const f = fakes({ users: [{ userId: "u-1", email: "a@example.com", isVerified: true }] });
  const a = answerFor("g-1", "a@example.com", { verified: false });
  const before = structuredClone(a);
  assert.deepEqual(await decide(a, ids, f.deps), before);
  assert.equal(f.zitadelCalls.length, 0);
  assert.deepEqual(f.log, [{ idp: "google", outcome: "not-proven" }]);
});

test("microsoftProvenLinks", async () => {
  const f = fakes({
    users: [{ userId: "u-2", email: "ann@example.com", isVerified: true }],
    me: workMe("ann@example.com"),
    org: workOrg,
  });
  const out = await decide(answerFor("m-1", "ann@example.com"), ids, f.deps);
  assert.equal(out.userId, "u-2");
  assert.deepEqual(addLinks(f)[0], ["addLink", "u-2", { idpId: "m-1", userId: "ext-42", userName: "External Name" }]);
  assert.deepEqual(f.log, [{ idp: "microsoft", outcome: "linked", proof: "domain" }]);
  assert.deepEqual(f.graphCalls[0], ["me", TOKEN]);
});

test("microsoftProvenNewAccountMarkedVerified", async () => {
  const f = fakes({ users: [], me: workMe("ann@example.com"), org: workOrg });
  const a = answerFor("m-1", "ann@example.com");
  const before = structuredClone(a);
  const out = await decide(a, ids, f.deps);
  assert.deepEqual(out.createUser.human.email, { email: "ann@example.com", isVerified: true });
  assert.deepEqual(out.addHumanUser.email, { email: "ann@example.com", isVerified: true });
  assert.equal(out.userId, undefined);
  assert.deepEqual(a, before);
  assert.equal(addLinks(f).length, 0);
  assert.deepEqual(f.log, [{ idp: "microsoft", outcome: "no-account", proof: "domain" }]);
});

test("microsoftNotProvenLeftUnverified", async () => {
  const f = fakes({
    users: [{ userId: "u-2", email: "ann@gmail.com", isVerified: true }],
    me: workMe("ann@gmail.com"),
    org: workOrg,
  });
  const a = answerFor("m-1", "ann@gmail.com");
  const before = structuredClone(a);
  assert.deepEqual(await decide(a, ids, f.deps), before);
  assert.equal(f.zitadelCalls.length, 0);
  assert.deepEqual(f.log, [{ idp: "microsoft", outcome: "not-proven" }]);
});

test("linksAcrossCase", async () => {
  const f = fakes({
    users: [{ userId: "u-3", email: "rob@example.com", isVerified: true }],
    me: workMe("Rob@Example.com"),
    org: workOrg,
  });
  const out = await decide(answerFor("m-1", "Rob@Example.com"), ids, f.deps);
  assert.equal(out.userId, "u-3");
  const g = fakes({ users: [{ userId: "u-3", email: "ROB@example.com", isVerified: true }] });
  const out2 = await decide(answerFor("g-1", "rob@Example.com", { verified: true }), ids, g.deps);
  assert.equal(out2.userId, "u-3");
});

test("twoAccountsNeverLink", async () => {
  for (const second of [false, true]) {
    const f = fakes({
      users: [
        { userId: "u-1", email: "a@example.com", isVerified: true },
        { userId: "u-2", email: "a@example.com", isVerified: second },
      ],
    });
    const out = await decide(answerFor("g-1", "a@example.com", { verified: true }), ids, f.deps);
    assert.equal(addLinks(f).length, 0);
    assert.equal(out.userId, undefined);
    assert.equal(f.log[0].outcome, "ambiguous");
  }
});

test("unverifiedAccountNeverLinks", async () => {
  const f = fakes({ users: [{ userId: "u-1", email: "a@example.com", isVerified: false }] });
  const out = await decide(answerFor("g-1", "a@example.com", { verified: true }), ids, f.deps);
  assert.equal(addLinks(f).length, 0);
  assert.equal(out.userId, undefined);
  assert.equal(f.log[0].outcome, "unverified-account");
});

test("lookupThrowsLinksNothing", async () => {
  const f = fakes({ lookupThrows: true });
  const a = answerFor("g-1", "a@example.com", { verified: true });
  const before = structuredClone(a);
  assert.deepEqual(await decide(a, ids, f.deps), before);
  assert.equal(addLinks(f).length, 0);
  assert.deepEqual(f.log, [{ idp: "google", outcome: "error" }]);
});

test("addLinkThrowsLinksNothing", async () => {
  const f = fakes({ users: [{ userId: "u-1", email: "a@example.com", isVerified: true }], addLinkThrows: true });
  const a = answerFor("g-1", "a@example.com", { verified: true });
  const out = await decide(a, ids, f.deps);
  assert.equal(out.userId, undefined);
  assert.deepEqual(f.log, [{ idp: "google", outcome: "error" }]);
});

test("microsoftPersonalProof", async () => {
  const f = fakes({
    users: [{ userId: "u-5", email: "pat@outlook.com", isVerified: true }],
    me: { id: PERSONAL_ID, mail: null, userPrincipalName: "pat@outlook.com" },
  });
  const out = await decide(answerFor("m-1", "pat@outlook.com"), ids, f.deps);
  assert.equal(out.userId, "u-5");
  assert.deepEqual(f.log, [{ idp: "microsoft", outcome: "linked", proof: "personal" }]);
});

test("noAddress", async () => {
  const f = fakes();
  const a = { idpInformation: { idpId: "g-1", userId: "x", userName: "n" } };
  assert.deepEqual(await decide(a, ids, f.deps), a);
  assert.deepEqual(f.log, [{ idp: "google", outcome: "no-address" }]);
});

test("logsNoAddressOrToken", async () => {
  const address = "ann@example.com";
  const runs = [
    fakes({ users: [{ userId: "u", email: address, isVerified: true }], me: workMe(address), org: workOrg }),
    fakes({ users: [], me: workMe(address), org: workOrg }),
    fakes({ lookupThrows: true, me: workMe(address), org: workOrg }),
    fakes({ me: workMe("other@example.com"), org: workOrg }),
  ];
  for (const f of runs) {
    await decide(answerFor("m-1", address), ids, f.deps);
    const text = JSON.stringify(f.log);
    assert.ok(f.log.length > 0);
    assert.ok(!text.includes(address));
    assert.ok(!text.includes("example.com"));
    assert.ok(!text.includes(TOKEN));
  }
});

test("emptyConfiguredProviderIdCountsAsAbsent", async () => {
  for (const idpId of ["", undefined]) {
    const f = fakes();
    const a = answerFor(idpId, "a@example.com", { verified: true });
    if (idpId === undefined) delete a.idpInformation.idpId;
    const out = await decide(a, { googleIdpId: "", microsoftIdpId: "" }, f.deps);
    assert.equal(out, a);
    assert.deepEqual(f.log, []);
  }
});

const STAND_IN = "outlook_4B5AE38E7DD4654F@outlook.com";
const SIGN_IN = "yileny.blust@flatland.ch";
const ownDomainMe = { id: "4b5ae38e7dd4654f", mail: STAND_IN, userPrincipalName: SIGN_IN };

test("personalLinksBySignInName", async () => {
  const f = fakes({ users: [{ userId: "u-7", email: SIGN_IN, isVerified: true }], me: ownDomainMe });
  const out = await decide(answerFor("m-1", STAND_IN), ids, f.deps);
  assert.deepEqual(f.zitadelCalls[0], ["usersByEmail", SIGN_IN]);
  assert.equal(addLinks(f).length, 1);
  assert.equal(out.userId, "u-7");
  assert.deepEqual(f.log, [{ idp: "microsoft", outcome: "linked", proof: "personal" }]);
});

test("personalNewAccountGetsSignInName", async () => {
  const f = fakes({ users: [], me: ownDomainMe });
  const out = await decide(answerFor("m-1", STAND_IN), ids, f.deps);
  assert.deepEqual(out.createUser.human.email, { email: SIGN_IN, isVerified: true });
  assert.deepEqual(out.addHumanUser.email, { email: SIGN_IN, isVerified: true });
  assert.equal(out.userId, undefined);
});

test("personalLogCarriesNoAddress", async () => {
  for (const users of [[{ userId: "u-7", email: SIGN_IN, isVerified: true }], []]) {
    const f = fakes({ users, me: ownDomainMe });
    await decide(answerFor("m-1", STAND_IN), ids, f.deps);
    const text = JSON.stringify(f.log);
    assert.ok(f.log.length > 0);
    assert.ok(!text.toLowerCase().includes("outlook_"));
    assert.ok(!text.includes(SIGN_IN));
  }
});

test("personalUnverifiedAccountNeverLinks", async () => {
  const f = fakes({ users: [{ userId: "u-8", email: SIGN_IN, isVerified: false }], me: ownDomainMe });
  const out = await decide(answerFor("m-1", STAND_IN), ids, f.deps);
  assert.equal(out.userId, undefined);
  assert.equal(addLinks(f).length, 0);
  assert.deepEqual(f.log, [{ idp: "microsoft", outcome: "unverified-account", proof: "personal" }]);
});

// GitHub: ZITADEL calls every GitHub address verified without asking GitHub, so the answer always
// arrives verified, and the link check proves the address from the account's own list.
const ghVerified = (address) => [{ email: address, verified: true }];
const unverifiedEmail = (address) => ({ email: address, sendCode: {} });

test("markUnverified", () => {
  const a = answerFor("gh-1", "a@b.c", { verified: true });
  const before = structuredClone(a);
  const m = markUnverified(a);
  assert.deepEqual(a, before);
  assert.deepEqual(m.createUser.human.email, unverifiedEmail("a@b.c"));
  assert.deepEqual(m.addHumanUser.email, unverifiedEmail("a@b.c"));
  assert.deepEqual(markUnverified({ idpInformation: {} }), { idpInformation: {} });
});

test("githubProvenLinks", async () => {
  const f = fakes({ users: [{ userId: "u-2", email: "ann@example.com", isVerified: true }], emails: ghVerified("ann@example.com") });
  const out = await decide(answerFor("gh-1", "ann@example.com", { verified: true }), ids, f.deps);
  assert.equal(out.userId, "u-2");
  assert.deepEqual(addLinks(f)[0], ["addLink", "u-2", { idpId: "gh-1", userId: "ext-42", userName: "External Name" }]);
  assert.deepEqual(f.log, [{ idp: "github", outcome: "linked", proof: "github" }]);
  assert.deepEqual(f.githubCalls, [["emails", TOKEN]]);
  assert.equal(f.graphCalls.length, 0);
});

test("githubProvenNewAccountStaysVerified", async () => {
  const f = fakes({ users: [], emails: ghVerified("ann@example.com") });
  const out = await decide(answerFor("gh-1", "ann@example.com", { verified: true }), ids, f.deps);
  assert.deepEqual(out.createUser.human.email, { email: "ann@example.com", isVerified: true });
  assert.deepEqual(out.addHumanUser.email, { email: "ann@example.com", isVerified: true });
  assert.equal(out.userId, undefined);
  assert.deepEqual(f.log, [{ idp: "github", outcome: "no-account", proof: "github" }]);
});

test("githubNotProvenMarkedUnverifiedAndLinksNothing", async () => {
  const f = fakes({
    users: [{ userId: "u-2", email: "ann@example.com", isVerified: true }],
    emails: [{ email: "ann@example.com", verified: false }],
  });
  const a = answerFor("gh-1", "ann@example.com", { verified: true });
  const before = structuredClone(a);
  const out = await decide(a, ids, f.deps);
  assert.deepEqual(a, before);
  assert.deepEqual(out.createUser.human.email, unverifiedEmail("ann@example.com"));
  assert.deepEqual(out.addHumanUser.email, unverifiedEmail("ann@example.com"));
  assert.equal(out.userId, undefined);
  assert.equal(f.zitadelCalls.length, 0);
  assert.deepEqual(f.log, [{ idp: "github", outcome: "not-proven" }]);
});

test("githubErrorMarkedUnverified", async () => {
  const f = fakes({ users: [{ userId: "u-2", email: "ann@example.com", isVerified: true }], githubThrows: true });
  const out = await decide(answerFor("gh-1", "ann@example.com", { verified: true }), ids, f.deps);
  assert.deepEqual(out.createUser.human.email, unverifiedEmail("ann@example.com"));
  assert.deepEqual(out.addHumanUser.email, unverifiedEmail("ann@example.com"));
  assert.equal(f.zitadelCalls.length, 0);
  assert.deepEqual(f.log, [{ idp: "github", outcome: "not-proven" }]);
});

test("githubUnverifiedAccountNeverLinks", async () => {
  const f = fakes({ users: [{ userId: "u-2", email: "ann@example.com", isVerified: false }], emails: ghVerified("ann@example.com") });
  const out = await decide(answerFor("gh-1", "ann@example.com", { verified: true }), ids, f.deps);
  assert.equal(out.userId, undefined);
  assert.equal(addLinks(f).length, 0);
  assert.deepEqual(f.log, [{ idp: "github", outcome: "unverified-account", proof: "github" }]);
});

test("githubAlreadyLinkedAsksNothing", async () => {
  const f = fakes({ emails: ghVerified("ann@example.com") });
  const a = answerFor("gh-1", "ann@example.com", { verified: true, userId: "u-9" });
  assert.equal(await decide(a, ids, f.deps), a);
  assert.equal(f.githubCalls.length, 0);
  assert.deepEqual(f.log, [{ idp: "github", outcome: "already-linked" }]);
});

test("githubLogsNoAddressOrToken", async () => {
  const address = "ann@example.com";
  const runs = [
    fakes({ users: [{ userId: "u", email: address, isVerified: true }], emails: ghVerified(address) }),
    fakes({ users: [], emails: ghVerified(address) }),
    fakes({ githubThrows: true }),
    fakes({ emails: ghVerified("other@example.com") }),
  ];
  for (const f of runs) {
    await decide(answerFor("gh-1", address, { verified: true }), ids, f.deps);
    const text = JSON.stringify(f.log);
    assert.ok(f.log.length > 0);
    assert.ok(!text.includes(address));
    assert.ok(!text.includes("example.com"));
    assert.ok(!text.includes(TOKEN));
  }
});

test("withoutGitHubConfiguredAGitHubAnswerIsUntouched", async () => {
  const f = fakes({ emails: ghVerified("ann@example.com") });
  const a = answerFor("gh-1", "ann@example.com", { verified: true });
  assert.equal(await decide(a, { googleIdpId: "g-1", microsoftIdpId: "m-1", githubIdpId: "" }, f.deps), a);
  assert.deepEqual(f.log, []);
});

test("githubLookupThrowsLinksNothingAndLeavesItUnverified", async () => {
  const f = fakes({ lookupThrows: true, emails: ghVerified("ann@example.com") });
  const out = await decide(answerFor("gh-1", "ann@example.com", { verified: true }), ids, f.deps);
  assert.deepEqual(out.createUser.human.email, unverifiedEmail("ann@example.com"));
  assert.deepEqual(out.addHumanUser.email, unverifiedEmail("ann@example.com"));
  assert.equal(out.userId, undefined);
  assert.deepEqual(f.log, [{ idp: "github", outcome: "error" }]);
});

test("githubNoTokenMarkedUnverified", async () => {
  const f = fakes({ users: [{ userId: "u-2", email: "ann@example.com", isVerified: true }], emails: ghVerified("ann@example.com") });
  const out = await decide(answerFor("gh-1", "ann@example.com", { verified: true, token: "" }), ids, f.deps);
  assert.deepEqual(out.createUser.human.email, unverifiedEmail("ann@example.com"));
  assert.deepEqual(out.addHumanUser.email, unverifiedEmail("ann@example.com"));
  assert.equal(f.githubCalls.length, 0);
  assert.equal(f.zitadelCalls.length, 0);
  assert.deepEqual(f.log, [{ idp: "github", outcome: "not-proven" }]);
});

test("githubNoAddressMarkedUnverified", async () => {
  // An answer whose createUser carries an empty address and whose addHumanUser carries one:
  // addressOf finds none, and nothing of it may stay verified.
  const f = fakes({ emails: ghVerified("ann@example.com") });
  const a = answerFor("gh-1", "ann@example.com", { verified: true });
  a.createUser.human.email = { email: "", isVerified: true };
  const out = await decide(a, ids, f.deps);
  assert.deepEqual(out.createUser.human.email, unverifiedEmail(""));
  assert.deepEqual(out.addHumanUser.email, unverifiedEmail("ann@example.com"));
  assert.equal(f.githubCalls.length, 0);
  assert.deepEqual(f.log, [{ idp: "github", outcome: "no-address" }]);
});

test("githubTwoDifferentAddressesProveNeither", async () => {
  const f = fakes({ users: [{ userId: "u-2", email: "ann@example.com", isVerified: true }], emails: ghVerified("ann@example.com") });
  const a = answerFor("gh-1", "ann@example.com", { verified: true });
  a.addHumanUser.email = { email: "mallory@example.com", isVerified: true };
  const out = await decide(a, ids, f.deps);
  assert.deepEqual(out.createUser.human.email, unverifiedEmail("ann@example.com"));
  assert.deepEqual(out.addHumanUser.email, unverifiedEmail("mallory@example.com"));
  assert.equal(f.githubCalls.length, 0);
  assert.equal(f.zitadelCalls.length, 0);
  assert.deepEqual(f.log, [{ idp: "github", outcome: "not-proven" }]);
});

test("aVerifiedMicrosoftAnswerIsNotUnverified", async () => {
  // Only GitHub's answers are set to unverified; a Microsoft or Google answer that arrives
  // verified and is not proven comes back as it was.
  for (const [idpId, extra] of [["m-1", { me: workMe("other@example.com"), org: workOrg }], ["g-1", {}]]) {
    const f = fakes({ lookupThrows: true, ...extra });
    const a = answerFor(idpId, "ann@example.com", { verified: true });
    const out = await decide(a, ids, f.deps);
    assert.deepEqual(out.addHumanUser.email, { email: "ann@example.com", isVerified: true });
  }
});

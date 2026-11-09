import { test } from "node:test";
import assert from "node:assert/strict";
import { decide, addressOf, markVerified } from "../lib/decide.mjs";

const ids = { googleIdpId: "g-1", microsoftIdpId: "m-1" };
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

function fakes({ users = [], lookupThrows = false, addLinkThrows = false, me, org } = {}) {
  const log = [];
  const zitadelCalls = [];
  const graphCalls = [];
  return {
    log,
    zitadelCalls,
    graphCalls,
    deps: {
      log: (line) => log.push(line),
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

const STAND_IN = "outlook_7C1E5A9B2D4F6083@outlook.com";
const SIGN_IN = "pat.example@example.ch";
const ownDomainMe = { id: "7c1e5a9b2d4f6083", mail: STAND_IN, userPrincipalName: SIGN_IN };

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

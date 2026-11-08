import { test } from "node:test";
import assert from "node:assert/strict";
import { provenByMicrosoft } from "../lib/prove.mjs";

const PERSONAL_ID = "3b78a729f3094e70";
const GUID_ID = "6f1c2a9e-0b7d-4c55-9a3e-1d2f3a4b5c6d";

function fakeGraph({ me, org, meThrows = false }) {
  const calls = [];
  return {
    calls,
    async me(token) {
      calls.push(["me", token]);
      if (meThrows) throw new Error("graph down");
      return me;
    },
    async organization(token) {
      calls.push(["organization", token]);
      return org;
    },
  };
}

const orgOk = (...verifiedDomains) => ({ ok: true, verifiedDomains });

test("workAccountOnVerifiedDomain", async () => {
  const graph = fakeGraph({
    me: { id: GUID_ID, mail: "ann@example.com", userPrincipalName: "ann@example.com" },
    org: orgOk("example.com"),
  });
  assert.deepEqual(await provenByMicrosoft("t", "Ann@Example.com", graph), { proof: "domain", address: "ann@example.com" });
});

test("workMailOnVerifiedDomain", async () => {
  const graph = fakeGraph({
    me: { id: GUID_ID, mail: "ann@example.com", userPrincipalName: "ann@x.onmicrosoft.com" },
    org: orgOk("example.com", "x.onmicrosoft.com"),
  });
  assert.deepEqual(await provenByMicrosoft("t", "ann@example.com", graph), { proof: "domain", address: "ann@example.com" });
});

test("workAccountForeignDomain", async () => {
  const graph = fakeGraph({
    me: { id: GUID_ID, mail: "ann@gmail.com", userPrincipalName: "ann@gmail.com" },
    org: orgOk("example.com"),
  });
  assert.equal(await provenByMicrosoft("t", "ann@gmail.com", graph), null);
});

test("guestIsNotProven", async () => {
  const graph = fakeGraph({
    me: { id: GUID_ID, mail: "guest@partner.org", userPrincipalName: "guest_partner.org#EXT#@example.onmicrosoft.com" },
    org: orgOk("example.com", "example.onmicrosoft.com"),
  });
  assert.equal(await provenByMicrosoft("t", "guest@partner.org", graph), null);
});

test("personalWithoutMail", async () => {
  const graph = fakeGraph({
    me: { id: PERSONAL_ID, mail: null, userPrincipalName: "pat@outlook.com" },
    org: { ok: false, status: 403 },
  });
  assert.deepEqual(await provenByMicrosoft("t", "Pat@outlook.com", graph), { proof: "personal", address: "pat@outlook.com" });
});

test("guidIdWithFailingOrganization", async () => {
  const graph = fakeGraph({
    me: { id: GUID_ID, mail: "ann@example.com", userPrincipalName: "ann@example.com" },
    org: { ok: false, status: 403 },
  });
  assert.equal(await provenByMicrosoft("t", "ann@example.com", graph), null);
});

test("organization5xx", async () => {
  const graph = fakeGraph({
    me: { id: PERSONAL_ID, mail: null, userPrincipalName: "pat@outlook.com" },
    org: { ok: false, status: 503 },
  });
  assert.equal(await provenByMicrosoft("t", "pat@outlook.com", graph), null);
});

test("addressMismatch", async () => {
  const graph = fakeGraph({
    me: { id: GUID_ID, mail: "ann@example.com", userPrincipalName: "ann@example.com" },
    org: orgOk("example.com"),
  });
  assert.equal(await provenByMicrosoft("t", "boss@example.com", graph), null);
});

test("meThrows", async () => {
  const graph = fakeGraph({ meThrows: true });
  assert.equal(await provenByMicrosoft("t", "ann@example.com", graph), null);
});

const STAND_IN = "outlook_4B5AE38E7DD4654F@outlook.com";
const SIGN_IN = "yileny.blust@flatland.ch";
const ownDomainMe = { id: "4b5ae38e7dd4654f", mail: STAND_IN, userPrincipalName: SIGN_IN };

test("personalOnOwnDomainUsesSignInName", async () => {
  const graph = fakeGraph({ me: ownDomainMe, org: { ok: false, status: 403 } });
  assert.deepEqual(await provenByMicrosoft("t", STAND_IN, graph), { proof: "personal", address: SIGN_IN });
});

test("personalAnswerMatchingSignInNameAlsoProven", async () => {
  const graph = fakeGraph({ me: ownDomainMe, org: { ok: false, status: 403 } });
  assert.deepEqual(await provenByMicrosoft("t", SIGN_IN, graph), { proof: "personal", address: SIGN_IN });
});

test("personalSignInNameNotAnEmail", async () => {
  const graph = fakeGraph({
    me: { id: "4b5ae38e7dd4654f", mail: STAND_IN, userPrincipalName: "+41791234567" },
    org: { ok: false, status: 403 },
  });
  assert.equal(await provenByMicrosoft("t", STAND_IN, graph), null);
});

test("personalAnswerOfAnotherAccount", async () => {
  const graph = fakeGraph({ me: ownDomainMe, org: { ok: false, status: 403 } });
  assert.equal(await provenByMicrosoft("t", "someone@else.com", graph), null);
});

test("workAccountKeepsMail", async () => {
  const graph = fakeGraph({
    me: { id: GUID_ID, mail: "ann@example.com", userPrincipalName: "ann@x.onmicrosoft.com" },
    org: orgOk("example.com"),
  });
  assert.deepEqual(await provenByMicrosoft("t", "ann@example.com", graph), { proof: "domain", address: "ann@example.com" });
});

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
  assert.equal(await provenByMicrosoft("t", "Ann@Example.com", graph), "domain");
});

test("workMailOnVerifiedDomain", async () => {
  const graph = fakeGraph({
    me: { id: GUID_ID, mail: "ann@example.com", userPrincipalName: "ann@x.onmicrosoft.com" },
    org: orgOk("example.com", "x.onmicrosoft.com"),
  });
  assert.equal(await provenByMicrosoft("t", "ann@example.com", graph), "domain");
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
  assert.equal(await provenByMicrosoft("t", "Pat@outlook.com", graph), "personal");
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

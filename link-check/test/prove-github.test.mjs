import { test } from "node:test";
import assert from "node:assert/strict";
import { provenByGitHub } from "../lib/prove.mjs";

function fakeGitHub({ emails, throws = false }) {
  const calls = [];
  return {
    calls,
    async emails(token) {
      calls.push(["emails", token]);
      if (throws) throw new Error("github down");
      return emails;
    },
  };
}

test("verifiedEntryProves", async () => {
  const github = fakeGitHub({ emails: [{ email: "ann@example.com", verified: true }] });
  assert.deepEqual(await provenByGitHub("t", "ann@example.com", github), { proof: "github", address: "ann@example.com" });
  assert.deepEqual(github.calls, [["emails", "t"]]);
});

test("aVerifiedEntryThatIsNotPrimaryStillProves", async () => {
  // ZITADEL takes the public email first, which need not be the primary one; what proves it is
  // that GitHub verified it, not which entry is primary.
  const github = fakeGitHub({
    emails: [
      { email: "ann@example.com", verified: true },
      { email: "ann@work.example", verified: true },
    ],
  });
  assert.deepEqual(await provenByGitHub("t", "ann@work.example", github), { proof: "github", address: "ann@work.example" });
});

test("comparedWithoutCase", async () => {
  const github = fakeGitHub({ emails: [{ email: "Ann@Example.com", verified: true }] });
  assert.deepEqual(await provenByGitHub("t", "ann@example.com", github), { proof: "github", address: "ann@example.com" });
});

test("unverifiedEntryIsNotProven", async () => {
  const github = fakeGitHub({ emails: [{ email: "ann@example.com", verified: false }] });
  assert.equal(await provenByGitHub("t", "ann@example.com", github), null);
});

test("addressNotOnTheAccountIsNotProven", async () => {
  const github = fakeGitHub({ emails: [{ email: "other@example.com", verified: true }] });
  assert.equal(await provenByGitHub("t", "ann@example.com", github), null);
});

test("anErrorIsNotProven", async () => {
  assert.equal(await provenByGitHub("t", "ann@example.com", fakeGitHub({ throws: true })), null);
});

test("noTokenAsksNothing", async () => {
  const github = fakeGitHub({ emails: [{ email: "ann@example.com", verified: true }] });
  for (const token of [undefined, null, ""]) assert.equal(await provenByGitHub(token, "ann@example.com", github), null);
  assert.equal(github.calls.length, 0);
});

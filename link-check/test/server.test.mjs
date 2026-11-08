import { test } from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "../server.mjs";
import { JwtError } from "../lib/jwt.mjs";

async function start(overrides = {}) {
  const logs = [];
  const calls = [];
  const server = createServer({
    verifier: { verify: async (t) => ({ response: { token: t } }) },
    decide: async (answer, ids) => {
      calls.push({ answer, ids });
      return { ...answer, decided: true };
    },
    graph: {},
    zitadel: {},
    log: (l) => logs.push(l),
    ...overrides,
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const base = `http://127.0.0.1:${server.address().port}`;
  return { base, logs, calls, close: () => new Promise((r) => server.close(r)) };
}

test("callRunsDecideWithQueryIds", async () => {
  const s = await start();
  try {
    const res = await fetch(`${s.base}/link-check/call?google=g1&microsoft=m1`, { method: "POST", body: "tok" });
    assert.equal(res.status, 200);
    assert.match(res.headers.get("content-type"), /^application\/json/);
    assert.deepEqual(await res.json(), { token: "tok", decided: true });
    assert.deepEqual(s.calls[0].ids, { googleIdpId: "g1", microsoftIdpId: "m1" });
    await fetch(`${s.base}/link-check/call`, { method: "POST", body: "tok" });
    assert.deepEqual(s.calls[1].ids, { googleIdpId: "", microsoftIdpId: "" });
  } finally {
    await s.close();
  }
});

test("badSignatureIs401", async () => {
  const s = await start({ verifier: { verify: async () => { throw new JwtError("bad"); } } });
  try {
    const res = await fetch(`${s.base}/link-check/call`, { method: "POST", body: "tok" });
    assert.equal(res.status, 401);
    assert.equal(await res.text(), "");
    assert.deepEqual(s.logs, [{ outcome: "bad-signature" }]);
    assert.equal(s.calls.length, 0);
  } finally {
    await s.close();
  }
});

test("decideThrowingIs500", async () => {
  const s = await start({ decide: async () => { throw new Error("secret@example.com"); } });
  try {
    const res = await fetch(`${s.base}/link-check/call`, { method: "POST", body: "tok" });
    assert.equal(res.status, 500);
    assert.equal(await res.text(), "");
    assert.deepEqual(s.logs, [{ outcome: "server-error" }]);
  } finally {
    await s.close();
  }
});

test("responseNotAnObjectIs400", async () => {
  for (const payload of [{}, { response: null }, { response: "x" }]) {
    const s = await start({ verifier: { verify: async () => payload } });
    try {
      const res = await fetch(`${s.base}/link-check/call`, { method: "POST", body: "tok" });
      assert.equal(res.status, 400);
      assert.equal(await res.text(), "");
      assert.deepEqual(s.logs, [{ outcome: "bad-payload" }]);
    } finally {
      await s.close();
    }
  }
});

test("bodyOverOneMiBIs413", async () => {
  const s = await start();
  try {
    const res = await fetch(`${s.base}/link-check/call`, { method: "POST", body: "x".repeat(1024 * 1024 + 1) });
    assert.equal(res.status, 413);
    assert.equal(await res.text(), "");
    assert.equal(s.calls.length, 0);
  } finally {
    await s.close();
  }
});

test("health", async () => {
  const s = await start();
  try {
    const res = await fetch(`${s.base}/link-check/health`);
    assert.equal(res.status, 200);
    assert.equal(await res.text(), "ok");
  } finally {
    await s.close();
  }
});

test("otherPathIs404", async () => {
  const s = await start();
  try {
    assert.equal((await fetch(`${s.base}/nope`)).status, 404);
    assert.equal((await fetch(`${s.base}/link-check/call`)).status, 404);
    assert.equal((await fetch(`${s.base}/link-check/health`, { method: "POST", body: "x" })).status, 404);
  } finally {
    await s.close();
  }
});

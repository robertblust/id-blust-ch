import { test } from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "../server.mjs";
import { JwtError, REASONS } from "../lib/jwt.mjs";

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
  const s = await start({ verifier: { verify: async () => { throw new JwtError("signature"); } } });
  try {
    const res = await fetch(`${s.base}/link-check/call`, { method: "POST", body: "tok" });
    assert.equal(res.status, 401);
    assert.equal(await res.text(), "");
    assert.deepEqual(s.logs, [{ outcome: "bad-jwt", reason: "signature" }]);
    assert.equal(s.calls.length, 0);
  } finally {
    await s.close();
  }
});

test("everyJwtReasonIsLogged", async () => {
  for (const reason of REASONS) {
    const s = await start({ verifier: { verify: async () => { throw new JwtError(reason); } } });
    try {
      const res = await fetch(`${s.base}/link-check/call`, { method: "POST", body: "tok" });
      assert.equal(res.status, 401);
      assert.deepEqual(s.logs, [{ outcome: "bad-jwt", reason }]);
    } finally {
      await s.close();
    }
  }
});

test("verifiedPayloadLogsHeaderAndClaimNamesOnly", async () => {
  const header = { alg: "RS256", typ: "JWT", kid: "k-secret" };
  const payload = { response: { a: "a@example.com" }, iss: "SECRET-ISS", zeta: 1 };
  payload["n".repeat(64)] = 1;
  payload["n".repeat(65)] = 1;
  const body = `${Buffer.from(JSON.stringify(header)).toString("base64url")}.x.y`;
  const s = await start({ verifier: { verify: async () => payload } });
  try {
    await fetch(`${s.base}/link-check/call`, { method: "POST", body });
    assert.equal(s.logs.length, 1);
    assert.deepEqual(s.logs[0], { outcome: "jwt", alg: "RS256", typ: "JWT", claims: ["iss", "n".repeat(64), "response", "zeta"] });
    const text = JSON.stringify(s.logs);
    for (const leak of ["example.com", "SECRET", "k-secret", body]) assert.ok(!text.includes(leak), leak);
  } finally {
    await s.close();
  }
});

test("typIsOmittedWhenNotAShortString", async () => {
  for (const typ of [5, "t".repeat(33), undefined]) {
    const s = await start();
    try {
      const body = `${Buffer.from(JSON.stringify({ alg: "RS256", typ })).toString("base64url")}.x.y`;
      await fetch(`${s.base}/link-check/call`, { method: "POST", body });
      assert.deepEqual(s.logs[0], { outcome: "jwt", alg: "RS256", claims: ["response"] });
    } finally {
      await s.close();
    }
  }
});

test("claimNamesAreCappedAtFifty", async () => {
  const payload = { response: {} };
  for (let i = 0; i < 80; i++) payload[`c${String(i).padStart(2, "0")}`] = i;
  const s = await start({ verifier: { verify: async () => payload } });
  try {
    await fetch(`${s.base}/link-check/call`, { method: "POST", body: "a.b.c" });
    assert.equal(s.logs[0].claims.length, 50);
    assert.deepEqual(s.logs[0].claims, [...s.logs[0].claims].sort());
    assert.equal(s.logs[0].alg, undefined);
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
    assert.deepEqual(s.logs, [{ outcome: "jwt", claims: ["response"] }, { outcome: "server-error" }]);
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
      assert.deepEqual(s.logs, [{ outcome: "jwt", claims: Object.keys(payload).sort() }, { outcome: "bad-payload" }]);
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

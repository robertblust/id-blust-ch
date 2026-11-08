import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, createVerify } from "node:crypto";
import { zitadelClient } from "../lib/zitadel.mjs";

const { publicKey, privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const pem = privateKey.export({ type: "pkcs8", format: "pem" });
const key = { keyId: "kid1", key: pem, userId: "u1" };
const issuer = "https://id.example";

function fake({ expiresIn = 3600, api = { status: 200, body: {} } } = {}) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith("/oauth/v2/token")) {
      return new Response(JSON.stringify({ access_token: "T" + calls.length, expires_in: expiresIn }), { status: 200 });
    }
    return new Response(JSON.stringify(api.body), { status: api.status });
  };
  fn.calls = calls;
  return fn;
}
const tokenCalls = (f) => f.calls.filter((c) => c.url.endsWith("/oauth/v2/token"));
const dec = (s) => JSON.parse(Buffer.from(s, "base64url").toString());

test("assertionVerifies", async () => {
  const fetch = fake();
  await zitadelClient({ issuer, key, fetch, now: () => 1_000_000_000 }).usersByEmail("a@example.com");
  const req = tokenCalls(fetch)[0];
  assert.equal(req.url, `${issuer}/oauth/v2/token`);
  const form = new URLSearchParams(req.init.body);
  assert.equal(form.get("grant_type"), "urn:ietf:params:oauth:grant-type:jwt-bearer");
  assert.equal(form.get("scope"), "openid urn:zitadel:iam:org:project:id:zitadel:aud");
  const [h, c, s] = form.get("assertion").split(".");
  assert.deepEqual(dec(h), { alg: "RS256", kid: "kid1" });
  assert.deepEqual(dec(c), { iss: "u1", sub: "u1", aud: issuer, iat: 1_000_000, exp: 1_000_300 });
  const v = createVerify("RSA-SHA256").update(`${h}.${c}`);
  assert.ok(v.verify(publicKey, Buffer.from(s, "base64url")));
});

test("tokenIsReused", async () => {
  const fetch = fake();
  const z = zitadelClient({ issuer, key, fetch, now: () => 0 });
  await z.usersByEmail("a@example.com");
  await z.usersByEmail("b@example.com");
  assert.equal(tokenCalls(fetch).length, 1);
  assert.equal(fetch.calls[1].init.headers.Authorization, "Bearer T1");
});

test("tokenRenewsNearExpiry", async () => {
  const fetch = fake({ expiresIn: 3600 });
  let t = 0;
  const z = zitadelClient({ issuer, key, fetch, now: () => t });
  await z.usersByEmail("a@example.com");
  t = (3600 - 61) * 1000;
  await z.usersByEmail("a@example.com");
  assert.equal(tokenCalls(fetch).length, 1);
  t = (3600 - 60) * 1000;
  await z.usersByEmail("a@example.com");
  assert.equal(tokenCalls(fetch).length, 2);
});

test("usersByEmailQuery", async () => {
  const fetch = fake({
    api: {
      status: 200,
      body: {
        result: [
          { userId: "1", human: { email: { email: "A@Example.com", isVerified: true } } },
          { userId: "2", human: { email: { email: "a@example.com" } } },
        ],
      },
    },
  });
  const users = await zitadelClient({ issuer, key, fetch }).usersByEmail("a@example.com");
  assert.deepEqual(users, [
    { userId: "1", email: "A@Example.com", isVerified: true },
    { userId: "2", email: "a@example.com", isVerified: false },
  ]);
  const call = fetch.calls[1];
  assert.equal(call.url, `${issuer}/v2/users`);
  assert.equal(call.init.method, "POST");
  assert.equal(call.init.headers["Content-Type"], "application/json");
  assert.deepEqual(JSON.parse(call.init.body), {
    queries: [{ emailQuery: { emailAddress: "a@example.com", method: "TEXT_QUERY_METHOD_EQUALS_IGNORE_CASE" } }],
  });
});

test("usersByEmailNeverLimitsToOne", async () => {
  const fetch = fake({ api: { status: 200, body: {} } });
  assert.deepEqual(await zitadelClient({ issuer, key, fetch }).usersByEmail("a@example.com"), []);
  const body = JSON.parse(fetch.calls[1].init.body);
  for (const limit of [body.limit, body.query?.limit]) {
    assert.ok(limit === undefined || Number(limit) >= 10);
  }
});

test("addLinkBody", async () => {
  const fetch = fake();
  await zitadelClient({ issuer, key, fetch }).addLink("u9", { idpId: "i", userId: "ext", userName: "n" });
  const call = fetch.calls[1];
  assert.equal(call.url, `${issuer}/v2/users/u9/links`);
  assert.equal(call.init.method, "POST");
  assert.deepEqual(JSON.parse(call.init.body), { idpLink: { idpId: "i", userId: "ext", userName: "n" } });
});

test("nullKeyThrows", async () => {
  const fetch = fake();
  const z = zitadelClient({ issuer, key: null, fetch });
  await assert.rejects(z.usersByEmail("a@example.com"), { message: "no key" });
  await assert.rejects(z.addLink("u", { idpId: "i", userId: "e", userName: "n" }), { message: "no key" });
  assert.equal(fetch.calls.length, 0);
});

test("errorCarriesNoBody", async () => {
  const fetch = fake({ api: { status: 500, body: { detail: "SECRET-BODY a@example.com" } } });
  const z = zitadelClient({ issuer, key, fetch });
  for (const p of [z.usersByEmail("a@example.com"), z.addLink("u", { idpId: "i", userId: "e", userName: "n" })]) {
    await assert.rejects(p, (e) => /500/.test(e.message) && !/SECRET|example\.com|BEGIN/.test(e.message));
  }
});

test("tokenFailureCarriesNoBody", async () => {
  const fetch = async () => new Response("SECRET-BODY", { status: 400 });
  await assert.rejects(zitadelClient({ issuer, key, fetch }).usersByEmail("a@example.com"), (e) => /400/.test(e.message) && !/SECRET/.test(e.message));
});

test("zitadelNonJsonBodyLeaksNothing", async () => {
  const bad = (url) => new Response("SECRET-BODY a@example.com", { status: 200 });
  const leak = (e) => /unexpected body/.test(e.message) && !/SECRET|example\.com/.test(e.message);
  await assert.rejects(zitadelClient({ issuer, key, fetch: async (u) => bad(u) }).usersByEmail("a@example.com"), leak);
  const api = async (u) => (String(u).endsWith("/oauth/v2/token") ? new Response(JSON.stringify({ access_token: "t", expires_in: 3600 })) : bad(u));
  await assert.rejects(zitadelClient({ issuer, key, fetch: api }).usersByEmail("a@example.com"), leak);
});

test("resultNotAnArrayThrows", async () => {
  const fetch = fake({ api: { status: 200, body: { result: "x" } } });
  await assert.rejects(zitadelClient({ issuer, key, fetch }).usersByEmail("a@example.com"), /unexpected/);
});

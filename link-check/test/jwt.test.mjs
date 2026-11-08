import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, createSign, sign } from "node:crypto";
import { jwtVerifier, JwtError } from "../lib/jwt.mjs";

const ISSUER = "https://id.example.test";
const b64 = (v) => Buffer.from(typeof v === "string" ? v : JSON.stringify(v)).toString("base64url");

function rsaKey(kid) {
  const { publicKey, privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  return { kid, privateKey, jwk: { ...publicKey.export({ format: "jwk" }), kid, use: "sig", alg: "RS256" } };
}
function ecKey(kid) {
  const { publicKey, privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  return { kid, privateKey, jwk: { ...publicKey.export({ format: "jwk" }), kid, use: "sig", alg: "ES256" } };
}
function token(key, payload, alg = "RS256") {
  const input = `${b64({ alg, kid: key.kid })}.${b64(payload)}`;
  const sig =
    alg === "RS256"
      ? createSign("RSA-SHA256").update(input).sign(key.privateKey)
      : sign("sha256", Buffer.from(input), { key: key.privateKey, dsaEncoding: "ieee-p1363" });
  return `${input}.${sig.toString("base64url")}`;
}
/** A fake fetch serving the given key sets in turn (the last repeats), counting calls. */
function keysFetch(...sets) {
  const f = async (url) => {
    assert.equal(url, `${ISSUER}/oauth/v2/keys`);
    const set = sets[Math.min(f.calls, sets.length - 1)];
    f.calls += 1;
    return new Response(JSON.stringify({ keys: set.map((k) => k.jwk) }), { status: 200 });
  };
  f.calls = 0;
  return f;
}

test("verifiesRs256", async () => {
  const k = rsaKey("a");
  const v = jwtVerifier({ issuer: ISSUER, fetch: keysFetch([k]) });
  assert.deepEqual(await v.verify(token(k, { response: { x: 1 } })), { response: { x: 1 } });
});

test("verifiesEs256", async () => {
  const k = ecKey("e");
  const v = jwtVerifier({ issuer: ISSUER, fetch: keysFetch([k]) });
  assert.deepEqual(await v.verify(token(k, { n: 2 }, "ES256")), { n: 2 });
});

test("refusesNone", async () => {
  const k = rsaKey("a");
  const v = jwtVerifier({ issuer: ISSUER, fetch: keysFetch([k]) });
  const none = `${b64({ alg: "none", kid: "a" })}.${b64({ n: 1 })}.`;
  await assert.rejects(v.verify(none), JwtError);
  const hs = `${b64({ alg: "HS256", kid: "a" })}.${b64({ n: 1 })}.${b64("x")}`;
  await assert.rejects(v.verify(hs), JwtError);
});

test("refusesForeignKey", async () => {
  const known = rsaKey("a");
  const foreign = rsaKey("a");
  const v = jwtVerifier({ issuer: ISSUER, fetch: keysFetch([known]) });
  await assert.rejects(v.verify(token(foreign, { n: 1 })), JwtError);
});

test("refetchesOnUnknownKid", async () => {
  const old = rsaKey("old");
  const fresh = rsaKey("new");
  const f = keysFetch([old], [old, fresh]);
  const v = jwtVerifier({ issuer: ISSUER, fetch: f });
  assert.deepEqual(await v.verify(token(fresh, { n: 1 })), { n: 1 });
  assert.equal(f.calls, 2);
  assert.deepEqual(await v.verify(token(old, { n: 2 })), { n: 2 });
  assert.equal(f.calls, 2, "cached after the refetch");
});

test("unknownKidAfterRefetchRefused", async () => {
  const old = rsaKey("old");
  const stranger = rsaKey("zzz");
  const f = keysFetch([old], [old]);
  const v = jwtVerifier({ issuer: ISSUER, fetch: f });
  await assert.rejects(v.verify(token(stranger, { n: 1 })), JwtError);
  assert.equal(f.calls, 2);
});

test("refusesExpired", async () => {
  const k = rsaKey("a");
  const v = jwtVerifier({ issuer: ISSUER, fetch: keysFetch([k]) });
  const past = Math.floor(Date.now() / 1000) - 10;
  await assert.rejects(v.verify(token(k, { exp: past })), JwtError);
  const future = Math.floor(Date.now() / 1000) + 600;
  assert.deepEqual(await v.verify(token(k, { exp: future })), { exp: future });
});

test("keyFetchFailureIsNotAJwtError", async () => {
  const k = rsaKey("a");
  const v = jwtVerifier({ issuer: ISSUER, fetch: async () => new Response("", { status: 503 }) });
  await assert.rejects(v.verify(token(k, {})), (e) => !(e instanceof JwtError));
});

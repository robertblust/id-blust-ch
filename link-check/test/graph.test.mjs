import { test } from "node:test";
import assert from "node:assert/strict";
import { graphClient } from "../lib/graph.mjs";

function fakeFetch(answer) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url: String(url), init });
    const { status = 200, body = {} } = typeof answer === "function" ? answer(url) : answer;
    return new Response(JSON.stringify(body), { status });
  };
  fn.calls = calls;
  return fn;
}

test("meSelectsThreeFields", async () => {
  const fetch = fakeFetch({ body: { id: "abc", mail: null, userPrincipalName: "a@example.com", extra: 1 } });
  const me = await graphClient({ fetch }).me("tok");
  assert.deepEqual(me, { id: "abc", mail: null, userPrincipalName: "a@example.com" });
  assert.equal(fetch.calls[0].url, "https://graph.microsoft.com/v1.0/me?$select=id,mail,userPrincipalName");
  assert.equal(fetch.calls[0].init.headers.Authorization, "Bearer tok");
});

test("meThrowsOnFailureWithoutBody", async () => {
  const fetch = fakeFetch({ status: 401, body: { secret: "s3cret-body" } });
  await assert.rejects(graphClient({ fetch }).me("tok"), (e) => /401/.test(e.message) && !/s3cret/.test(e.message));
});

test("organizationReadsDomains", async () => {
  const fetch = fakeFetch({
    body: { value: [{ verifiedDomains: [{ name: "example.com", isDefault: true, isInitial: false, type: "Managed" }, { name: "x.onmicrosoft.com", isDefault: false }] }] },
  });
  const org = await graphClient({ fetch }).organization("tok");
  assert.deepEqual(org, { ok: true, verifiedDomains: ["example.com", "x.onmicrosoft.com"] });
  assert.equal(fetch.calls[0].url, "https://graph.microsoft.com/v1.0/organization?$select=verifiedDomains");
  assert.equal(fetch.calls[0].init.headers.Authorization, "Bearer tok");
});

test("organizationFailureIsStatus", async () => {
  const fetch = fakeFetch({ status: 403, body: { error: "nope" } });
  assert.deepEqual(await graphClient({ fetch }).organization("tok"), { ok: false, status: 403 });
});

test("organizationUnexpectedShapeThrows", async () => {
  for (const body of [{}, { value: [] }, { value: [{}] }, { value: [{ verifiedDomains: "x" }] }, { value: [{ verifiedDomains: [{ nom: "a" }] }] }]) {
    await assert.rejects(graphClient({ fetch: fakeFetch({ body }) }).organization("tok"), /unexpected/);
  }
});

test("graphTimesOut", async () => {
  const fetch = () => new Promise(() => {});
  const started = Date.now();
  await assert.rejects(graphClient({ fetch, timeoutMs: 50 }).me("tok"));
  assert.ok(Date.now() - started < 1000);
  await assert.rejects(graphClient({ fetch, timeoutMs: 50 }).organization("tok"));
});

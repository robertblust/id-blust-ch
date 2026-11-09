import { test } from "node:test";
import assert from "node:assert/strict";
import { githubClient } from "../lib/github.mjs";

function fakeFetch(answer) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url: String(url), init });
    const { status = 200, body = [] } = typeof answer === "function" ? answer(url) : answer;
    return new Response(typeof body === "string" ? body : JSON.stringify(body), { status });
  };
  fn.calls = calls;
  return fn;
}

test("emailsReadsTheList", async () => {
  const fetch = fakeFetch({
    body: [
      { email: "ann@example.com", verified: true, primary: true, visibility: "private" },
      { email: "ann@work.example", verified: false, primary: false, visibility: null },
    ],
  });
  const emails = await githubClient({ fetch }).emails("tok");
  assert.deepEqual(emails, [
    { email: "ann@example.com", verified: true },
    { email: "ann@work.example", verified: false },
  ]);
  assert.equal(fetch.calls[0].url, "https://api.github.com/user/emails?per_page=100");
  const headers = fetch.calls[0].init.headers;
  assert.equal(headers.Authorization, "Bearer tok");
  assert.equal(headers.Accept, "application/vnd.github+json");
  assert.equal(headers["X-GitHub-Api-Version"], "2022-11-28");
  assert.equal(headers["User-Agent"], "id.blust.ch-link-check");
});

test("emailsThrowsOnFailureWithoutBody", async () => {
  const fetch = fakeFetch({ status: 403, body: { message: "s3cret-body" } });
  await assert.rejects(githubClient({ fetch }).emails("tok"), (e) => /403/.test(e.message) && !/s3cret/.test(e.message));
});

test("emailsUnexpectedShapeThrows", async () => {
  for (const body of [{ email: "a@b.c" }, [{ email: 1, verified: true }], [{ email: "a@b.c", verified: "yes" }], [null]]) {
    await assert.rejects(githubClient({ fetch: fakeFetch({ body }) }).emails("tok"), /unexpected shape/);
  }
});

test("emailsNonJsonBodyLeaksNothing", async () => {
  const fetch = fakeFetch({ body: "<html>s3cret</html>" });
  await assert.rejects(githubClient({ fetch }).emails("tok"), (e) => /unexpected body/.test(e.message) && !/s3cret/.test(e.message));
});

test("githubTimesOut", async () => {
  const fetch = (_url, init) =>
    new Promise((_, reject) => init.signal.addEventListener("abort", () => reject(new Error("aborted"))));
  await assert.rejects(githubClient({ fetch, timeoutMs: 20 }).emails("tok"), /github timeout/);
});

/** @typedef {import("./prove.mjs").GitHub} GitHub */

/**
 * The real GitHub client. Every call aborts at timeoutMs. Errors carry a
 * status or a fixed phrase, never a body or a token. GitHub's REST API refuses
 * a request without a User-Agent, so it names one that carries no address.
 * @param {{ fetch?: typeof fetch, base?: string, timeoutMs?: number }} [options]
 * @returns {GitHub}
 */
export function githubClient({ fetch = globalThis.fetch, base = "https://api.github.com", timeoutMs = 3000 } = {}) {
  async function get(path, token) {
    const controller = new AbortController();
    let timer;
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(new Error("github timeout"));
      }, timeoutMs);
    });
    try {
      const request = (async () => {
        const res = await fetch(`${base}${path}`, {
          headers: {
            Authorization: `Bearer ${token}`,
            Accept: "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "id.blust.ch-link-check",
          },
          signal: controller.signal,
        });
        return { status: res.status, ok: res.ok, json: res.ok ? await res.json().catch(() => { throw new Error("github unexpected body"); }) : null };
      })();
      request.catch(() => {});
      return await Promise.race([request, timeout]);
    } finally {
      clearTimeout(timer);
    }
  }

  return {
    async emails(token) {
      const res = await get("/user/emails", token);
      if (!res.ok) throw new Error(`github emails ${res.status}`);
      const list = res.json;
      if (!Array.isArray(list) || list.some((e) => typeof e?.email !== "string" || typeof e?.verified !== "boolean")) {
        throw new Error("github emails unexpected shape");
      }
      return list.map(({ email, verified }) => ({ email, verified }));
    },
  };
}

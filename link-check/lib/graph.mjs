/** @typedef {import("./prove.mjs").Graph} Graph */

/**
 * The real Microsoft Graph client. Every call aborts at timeoutMs. Errors
 * carry a status or a fixed phrase, never a body or a token.
 * @param {{ fetch?: typeof fetch, base?: string, timeoutMs?: number }} [options]
 * @returns {Graph}
 */
export function graphClient({ fetch = globalThis.fetch, base = "https://graph.microsoft.com/v1.0", timeoutMs = 3000 } = {}) {
  async function get(path, token) {
    const controller = new AbortController();
    let timer;
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(new Error("graph timeout"));
      }, timeoutMs);
    });
    try {
      const request = (async () => {
        const res = await fetch(`${base}${path}`, {
          headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
          signal: controller.signal,
        });
        return { status: res.status, ok: res.ok, json: res.ok ? await res.json().catch(() => { throw new Error("graph unexpected body"); }) : null };
      })();
      request.catch(() => {});
      return await Promise.race([request, timeout]);
    } finally {
      clearTimeout(timer);
    }
  }

  return {
    async me(token) {
      const res = await get("/me?$select=id,mail,userPrincipalName", token);
      if (!res.ok) throw new Error(`graph me ${res.status}`);
      const { id, mail, userPrincipalName } = res.json ?? {};
      if (typeof id !== "string" || typeof userPrincipalName !== "string" || (mail != null && typeof mail !== "string")) {
        throw new Error("graph me unexpected shape");
      }
      return { id, mail: mail ?? null, userPrincipalName };
    },
    async organization(token) {
      const res = await get("/organization?$select=verifiedDomains", token);
      if (!res.ok) return { ok: false, status: res.status };
      const domains = res.json?.value?.[0]?.verifiedDomains;
      if (!Array.isArray(domains) || domains.some((d) => typeof d?.name !== "string")) {
        throw new Error("graph organization unexpected shape");
      }
      return { ok: true, verifiedDomains: domains.map((d) => d.name) };
    },
  };
}

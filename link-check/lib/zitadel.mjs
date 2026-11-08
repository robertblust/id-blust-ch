import { createSign } from "node:crypto";

/** @typedef {import("./decide.mjs").Zitadel} Zitadel */

const b64 = (v) => Buffer.from(typeof v === "string" ? v : JSON.stringify(v)).toString("base64url");

/**
 * The real ZITADEL client, signed in as the machine user by a JWT-bearer
 * grant. The token is reused until 60 seconds before it expires. Errors carry
 * a status or a fixed phrase, never a body, a token, the key or an address.
 * @param {{ issuer: string, key: { keyId: string, key: string, userId: string } | null, fetch?: typeof fetch, now?: () => number }} options
 * @returns {Zitadel}
 */
export function zitadelClient({ issuer, key, fetch = globalThis.fetch, now = () => Date.now() }) {
  let cached = null; // { token, renewAt }

  async function token() {
    if (!key) throw new Error("no key");
    if (cached && now() < cached.renewAt) return cached.token;
    const iat = Math.floor(now() / 1000);
    const input = `${b64({ alg: "RS256", kid: key.keyId })}.${b64({ iss: key.userId, sub: key.userId, aud: issuer, iat, exp: iat + 300 })}`;
    const signature = createSign("RSA-SHA256").update(input).sign(key.key).toString("base64url");
    const res = await fetch(`${issuer}/oauth/v2/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        scope: "openid urn:zitadel:iam:org:project:id:zitadel:aud",
        assertion: `${input}.${signature}`,
      }).toString(),
    });
    if (!res.ok) throw new Error(`zitadel token ${res.status}`);
    const { access_token, expires_in } = await res.json();
    if (typeof access_token !== "string" || !Number.isFinite(expires_in)) throw new Error("zitadel token unexpected shape");
    cached = { token: access_token, renewAt: now() + (expires_in - 60) * 1000 };
    return access_token;
  }

  async function post(path, body) {
    const tok = await token();
    const res = await fetch(`${issuer}${path}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${tok}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`zitadel ${res.status}`);
    return res.json();
  }

  return {
    async usersByEmail(address) {
      // No limit: a query limit of one could hide a stranger's same-address account.
      const out = await post("/v2/users", {
        queries: [{ emailQuery: { emailAddress: address, method: "TEXT_QUERY_METHOD_EQUALS_IGNORE_CASE" } }],
      });
      return (out.result ?? []).map((u) => ({
        userId: u.userId,
        email: u.human?.email?.email ?? "",
        isVerified: u.human?.email?.isVerified === true,
      }));
    },
    async addLink(userId, { idpId, userId: externalId, userName }) {
      await post(`/v2/users/${encodeURIComponent(userId)}/links`, { idpLink: { idpId, userId: externalId, userName } });
    },
  };
}

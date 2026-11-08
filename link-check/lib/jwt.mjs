import { createPublicKey, verify } from "node:crypto";

/** Why a token is refused: the only strings a log may carry about it. */
export const REASONS = new Set(["malformed", "alg", "no-kid", "unknown-kid", "signature", "expired"]);

/** A token that is not acceptable. Its `reason` is always one of REASONS. */
export class JwtError extends Error {
  constructor(reason) {
    const fixed = REASONS.has(reason) ? reason : "malformed";
    super(fixed);
    this.reason = fixed;
  }
}

const ALGS = {
  RS256: { options: (key) => key },
  ES256: { options: (key) => ({ key, dsaEncoding: "ieee-p1363" }) },
};

const decode = (part) => {
  try {
    return JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
  } catch {
    throw new JwtError("malformed");
  }
};

/**
 * Verifies compact JWTs against the issuer's published keys. Keys are cached
 * and fetched once more when a token names a kid the cache lacks. A failure to
 * fetch the keys is a plain Error, not a JwtError: the token is not at fault.
 * @param {{ issuer: string, fetch?: typeof fetch }} options
 * @returns {{ verify(compact: string): Promise<object> }}
 */
export function jwtVerifier({ issuer, fetch = globalThis.fetch }) {
  let keys = new Map(); // kid -> KeyObject
  let loading = null;

  function load() {
    loading ??= (async () => {
      try {
        const res = await fetch(`${issuer}/oauth/v2/keys`);
        if (!res.ok) throw new Error(`keys ${res.status}`);
        const body = await res.json();
        const next = new Map();
        for (const jwk of body?.keys ?? []) {
          if (typeof jwk?.kid !== "string") continue;
          try {
            next.set(jwk.kid, createPublicKey({ key: jwk, format: "jwk" }));
          } catch {
            // A key we cannot read is a key we do not trust.
          }
        }
        keys = next;
      } finally {
        loading = null;
      }
    })();
    return loading;
  }

  async function keyFor(kid) {
    if (keys.size === 0) await load();
    if (!keys.has(kid)) await load();
    return keys.get(kid);
  }

  return {
    async verify(compact) {
      const parts = typeof compact === "string" ? compact.trim().split(".") : [];
      if (parts.length !== 3) throw new JwtError("malformed");
      const header = decode(parts[0]);
      const alg = Object.hasOwn(ALGS, header?.alg) ? header.alg : null;
      if (!alg) throw new JwtError("alg");
      if (typeof header.kid !== "string") throw new JwtError("no-kid");
      const key = await keyFor(header.kid);
      if (!key) throw new JwtError("unknown-kid");
      let ok = false;
      try {
        ok = verify("sha256", Buffer.from(`${parts[0]}.${parts[1]}`), ALGS[alg].options(key), Buffer.from(parts[2], "base64url"));
      } catch {
        ok = false;
      }
      if (!ok) throw new JwtError("signature");
      const payload = decode(parts[1]);
      if (payload === null || typeof payload !== "object") throw new JwtError("malformed");
      if (payload.exp !== undefined && !(typeof payload.exp === "number" && payload.exp * 1000 > Date.now())) {
        throw new JwtError("expired");
      }
      return payload;
    },
  };
}

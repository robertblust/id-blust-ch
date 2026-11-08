/**
 * @typedef {object} Graph
 * @property {(token: string) => Promise<{ id: string, mail: string | null, userPrincipalName: string }>} me Throws on any failure.
 * @property {(token: string) => Promise<{ ok: true, verifiedDomains: string[] } | { ok: false, status: number }>} organization
 */

const PERSONAL_ID = /^[0-9a-f]{16}$/;

const lower = (s) => String(s).toLowerCase();

/** Exactly one "@", a local part, a domain with a dot, no whitespace. */
function looksLikeAddress(s) {
  if (typeof s !== "string" || /\s/.test(s)) return false;
  const parts = s.split("@");
  return parts.length === 2 && parts[0] !== "" && /^[^.].*\./.test(parts[1]) && !parts[1].endsWith(".");
}

/**
 * Whether Microsoft proves the address, and which address it proves. A work or
 * school account's mail (or user principal name where mail is empty) must
 * equal the answer's address and sit on a domain its tenant verified. A
 * personal account's proven address is its sign-in name, which Microsoft
 * verified when the account was made, whatever stand-in mail the answer holds.
 * @param {string} accessToken
 * @param {string} address The answer's address.
 * @param {Graph} graph
 * @returns {Promise<{ proof: "domain" | "personal", address: string } | null>}
 */
export async function provenByMicrosoft(accessToken, address, graph) {
  let me;
  try {
    me = await graph.me(accessToken);
  } catch {
    return null;
  }
  const org = await graph.organization(accessToken);
  if (org.ok) {
    const own = me.mail ? me.mail : me.userPrincipalName;
    if (!own || lower(own) !== lower(address)) return null;
    const domain = lower(own).split("@").pop();
    return org.verifiedDomains.some((d) => lower(d) === domain) ? { proof: "domain", address: own } : null;
  }
  if (org.status >= 400 && org.status < 500 && PERSONAL_ID.test(me.id)) {
    const theirs = [me.mail, me.userPrincipalName].filter(Boolean).map(lower);
    if (!theirs.includes(lower(address))) return null;
    if (!looksLikeAddress(me.userPrincipalName)) return null;
    return { proof: "personal", address: me.userPrincipalName };
  }
  return null;
}

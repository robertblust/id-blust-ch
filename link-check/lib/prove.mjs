/**
 * @typedef {object} GitHub
 * @property {(token: string) => Promise<Array<{ email: string, verified: boolean }>>} emails Throws on any failure.
 */

/**
 * @typedef {object} Graph
 * @property {(token: string) => Promise<{ id: string, mail: string | null, userPrincipalName: string }>} me Throws on any failure.
 * @property {(token: string) => Promise<{ ok: true, verifiedDomains: string[] } | { ok: false, status: number }>} organization
 */

const PERSONAL_ID = /^[0-9a-f]{16}$/;

const lower = (s) => String(s).toLowerCase();

/**
 * Exactly one "@"; a local part without whitespace, "#" or ","; a domain without
 * whitespace, "#", ",", ".." or a leading or trailing dot, ending in a label of
 * at least two letters.
 * @param {unknown} s
 * @returns {boolean}
 */
export function looksLikeAddress(s) {
  if (typeof s !== "string") return false;
  const parts = s.split("@");
  if (parts.length !== 2) return false;
  const [local, domain] = parts;
  if (local === "" || /[\s#,]/.test(local)) return false;
  if (/[\s#,]/.test(domain) || domain.includes("..")) return false;
  return /^[^.]+(\.[^.]+)*\.[A-Za-z]{2,}$/.test(domain);
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

/**
 * Whether GitHub proves the address. ZITADEL calls every address it takes from
 * GitHub verified without asking, so the address counts only when the
 * account's own list, GET /user/emails, holds it with verified true; GitHub
 * marks an address verified once the code it mailed there was entered. Which
 * entry is primary does not matter, since ZITADEL may have taken the public
 * email. Any error, or no token, proves nothing.
 * @param {string | undefined} accessToken
 * @param {string} address The answer's address.
 * @param {GitHub} github
 * @returns {Promise<{ proof: "github", address: string } | null>}
 */
export async function provenByGitHub(accessToken, address, github) {
  if (!accessToken) return null;
  let emails;
  try {
    emails = await github.emails(accessToken);
  } catch {
    return null;
  }
  return emails.some((e) => e.verified === true && lower(e.email) === lower(address)) ? { proof: "github", address } : null;
}

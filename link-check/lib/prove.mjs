/**
 * @typedef {object} Graph
 * @property {(token: string) => Promise<{ id: string, mail: string | null, userPrincipalName: string }>} me Throws on any failure.
 * @property {(token: string) => Promise<{ ok: true, verifiedDomains: string[] } | { ok: false, status: number }>} organization
 */

const PERSONAL_ID = /^[0-9a-f]{16}$/;

const lower = (s) => String(s).toLowerCase();

/**
 * Whether Microsoft proves the address: "domain" when it sits on a domain the
 * signed-in account's tenant has verified, "personal" for a personal account
 * whose own sign-in name is the address, null otherwise.
 * @param {string} accessToken
 * @param {string} address
 * @param {Graph} graph
 * @returns {Promise<"domain" | "personal" | null>}
 */
export async function provenByMicrosoft(accessToken, address, graph) {
  let me;
  try {
    me = await graph.me(accessToken);
  } catch {
    return null;
  }
  const own = me.mail ? me.mail : me.userPrincipalName;
  if (!own || lower(own) !== lower(address)) return null;

  const org = await graph.organization(accessToken);
  if (org.ok) {
    const domain = lower(address).split("@").pop();
    return org.verifiedDomains.some((d) => lower(d) === domain) ? "domain" : null;
  }
  if (org.status >= 400 && org.status < 500 && PERSONAL_ID.test(me.id)) return "personal";
  return null;
}

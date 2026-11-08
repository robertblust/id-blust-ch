import { provenByMicrosoft } from "./prove.mjs";

/** @typedef {import("./prove.mjs").Graph} Graph */
/**
 * @typedef {object} Zitadel
 * @property {(address: string) => Promise<Array<{ userId: string, email: string, isVerified: boolean }>>} usersByEmail
 * @property {(userId: string, link: { idpId: string, userId: string, userName: string }) => Promise<void>} addLink
 */

const lower = (s) => String(s).toLowerCase();

/**
 * The address the answer would create an account with, or null.
 * @param {object} answer
 * @returns {string | null}
 */
export function addressOf(answer) {
  return answer.createUser?.human?.email?.email ?? answer.addHumanUser?.email?.email ?? null;
}

/**
 * A copy of the answer whose email, where present, is verified.
 * @param {object} answer
 * @returns {object}
 */
export function markVerified(answer) {
  const copy = structuredClone(answer);
  if (copy.createUser?.human?.email) {
    copy.createUser.human.email = { email: copy.createUser.human.email.email, isVerified: true };
  }
  if (copy.addHumanUser?.email) {
    copy.addHumanUser.email = { email: copy.addHumanUser.email.email, isVerified: true };
  }
  return copy;
}

function googleVerified(answer, address) {
  const emails = [answer.createUser?.human?.email, answer.addHumanUser?.email];
  return emails.some((e) => e && e.isVerified === true && lower(e.email) === lower(address));
}

/**
 * Decides whether to link the external account to an existing one. Never
 * throws: on any error it logs "error" and returns the answer unchanged.
 * @param {object} answer ZITADEL's RetrieveIdentityProviderIntentResponse, protojson.
 * @param {{ googleIdpId: string, microsoftIdpId: string }} ids
 * @param {{ graph: Graph, zitadel: Zitadel, log: (line: object) => void }} deps
 * @returns {Promise<object>}
 */
export async function decide(answer, ids, deps) {
  let idp = "other";
  try {
    const idpId = answer.idpInformation?.idpId;
    // A provider id that is not configured is "", which no answer is of.
    if (idpId && idpId === ids.googleIdpId) idp = "google";
    else if (idpId && idpId === ids.microsoftIdpId) idp = "microsoft";
    else return answer;

    const done = (outcome, result, proof) => {
      deps.log(proof ? { idp, outcome, proof } : { idp, outcome });
      return result;
    };

    if (answer.userId) return done("already-linked", answer);

    const address = addressOf(answer);
    if (!address) return done("no-address", answer);

    let proof;
    let current = answer;
    if (idp === "google") {
      proof = googleVerified(answer, address) ? undefined : null;
    } else {
      proof = await provenByMicrosoft(answer.idpInformation.oauth?.accessToken, address, deps.graph);
      if (proof) current = markVerified(answer);
    }
    if (proof === null) return done("not-proven", answer);

    const users = (await deps.zitadel.usersByEmail(address)).filter((u) => lower(u.email) === lower(address));
    if (users.length === 0) return done("no-account", current, proof);
    if (users.length > 1) return done("ambiguous", current, proof);
    const [user] = users;
    if (!user.isVerified) return done("unverified-account", current, proof);

    await deps.zitadel.addLink(user.userId, {
      idpId: answer.idpInformation.idpId,
      userId: answer.idpInformation.userId,
      userName: answer.idpInformation.userName,
    });
    return done("linked", { ...current, userId: user.userId }, proof);
  } catch {
    try {
      deps.log({ idp, outcome: "error" });
    } catch {
      // a failing log must not turn into a throw
    }
    return answer;
  }
}

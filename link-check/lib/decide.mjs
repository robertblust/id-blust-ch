import { provenByMicrosoft, provenByGitHub } from "./prove.mjs";

/** @typedef {import("./prove.mjs").Graph} Graph */
/** @typedef {import("./prove.mjs").GitHub} GitHub */
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
 * @param {string} [address] Replaces the answer's address where given.
 * @returns {object}
 */
export function markVerified(answer, address) {
  const copy = structuredClone(answer);
  if (copy.createUser?.human?.email) {
    copy.createUser.human.email = { email: address ?? copy.createUser.human.email.email, isVerified: true };
  }
  if (copy.addHumanUser?.email) {
    copy.addHumanUser.email = { email: address ?? copy.addHumanUser.email.email, isVerified: true };
  }
  return copy;
}

/**
 * A copy of the answer whose email, where present, is not verified, in the
 * shape ZITADEL itself writes for an address it does not take as verified, so
 * the login mails a code before the account is used.
 * @param {object} answer
 * @returns {object}
 */
export function markUnverified(answer) {
  const copy = structuredClone(answer);
  if (copy.createUser?.human?.email) {
    copy.createUser.human.email = { email: copy.createUser.human.email.email, sendCode: {} };
  }
  if (copy.addHumanUser?.email) {
    copy.addHumanUser.email = { email: copy.addHumanUser.email.email, sendCode: {} };
  }
  return copy;
}

function sameAddressThroughout(answer, address) {
  const emails = [answer.createUser?.human?.email, answer.addHumanUser?.email].filter(Boolean);
  return emails.every((e) => typeof e.email === "string" && lower(e.email) === lower(address));
}

function googleVerified(answer, address) {
  const emails = [answer.createUser?.human?.email, answer.addHumanUser?.email];
  return emails.some((e) => e && e.isVerified === true && lower(e.email) === lower(address));
}

/**
 * Decides whether to link the external account to an existing one. Never
 * throws: on any error it logs "error" and returns the answer unchanged, but
 * for GitHub with its address unverified, since ZITADEL calls every GitHub
 * address verified and only the link check's proof may let that stand.
 * @param {object} answer ZITADEL's RetrieveIdentityProviderIntentResponse, protojson.
 * @param {{ googleIdpId: string, microsoftIdpId: string, githubIdpId?: string }} ids
 * @param {{ graph: Graph, github: GitHub, zitadel: Zitadel, log: (line: object) => void }} deps
 * @returns {Promise<object>}
 */
export async function decide(answer, ids, deps) {
  let idp = "other";
  try {
    const idpId = answer.idpInformation?.idpId;
    // A provider id that is not configured is "", which no answer is of.
    if (idpId && idpId === ids.googleIdpId) idp = "google";
    else if (idpId && idpId === ids.microsoftIdpId) idp = "microsoft";
    else if (idpId && idpId === ids.githubIdpId) idp = "github";
    else return answer;

    const done = (outcome, result, proof) => {
      deps.log(proof ? { idp, outcome, proof } : { idp, outcome });
      return result;
    };

    if (answer.userId) return done("already-linked", answer);

    let address = addressOf(answer);
    // Every GitHub exit that proves nothing leaves the address unverified, this one included.
    if (!address) return done("no-address", idp === "github" ? markUnverified(answer) : answer);

    let proof;
    let current = answer;
    if (idp === "google") {
      proof = googleVerified(answer, address) ? undefined : null;
    } else if (idp === "github") {
      // The proof covers one address, so both places the answer may carry one must hold it;
      // an answer whose two addresses differ proves neither.
      const proven = sameAddressThroughout(answer, address)
        ? await provenByGitHub(answer.idpInformation.oauth?.accessToken, address, deps.github)
        : null;
      if (!proven) return done("not-proven", markUnverified(answer));
      proof = proven.proof;
    } else {
      const proven = await provenByMicrosoft(answer.idpInformation.oauth?.accessToken, address, deps.graph);
      if (proven) {
        proof = proven.proof;
        address = proven.address;
        current = markVerified(answer, address);
      } else {
        proof = null;
      }
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
    if (idp !== "github") return answer;
    try {
      return markUnverified(answer);
    } catch {
      return answer;
    }
  }
}

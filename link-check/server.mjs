import http from "node:http";
import { pathToFileURL } from "node:url";
import { decide as realDecide } from "./lib/decide.mjs";
import { graphClient } from "./lib/graph.mjs";
import { githubClient } from "./lib/github.mjs";
import { zitadelClient } from "./lib/zitadel.mjs";
import { jwtVerifier, JwtError, REASONS } from "./lib/jwt.mjs";

/** The one call the link check answers; any other verified instance-signed JWT is refused. */
const RETRIEVE_INTENT_METHOD = "/zitadel.user.v2.UserService/RetrieveIdentityProviderIntent";

const MAX_BODY = 1024 * 1024;

class TooLarge extends Error {}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) {
        reject(new TooLarge());
        req.resume();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

/** Logs, for a verified token, its header's alg and typ and its claims' names, never a value. */
function claimsLine(compact, payload) {
  let header = null;
  try {
    header = JSON.parse(Buffer.from(String(compact).trim().split(".")[0], "base64url").toString("utf8"));
  } catch {
    // the verifier has accepted it; a header we cannot read here is simply not logged
  }
  const line = { outcome: "jwt" };
  const short = (v, max) => typeof v === "string" && v.length <= max;
  if (short(header?.alg, 32)) line.alg = header.alg;
  if (short(header?.typ, 32)) line.typ = header.typ;
  const names = payload !== null && typeof payload === "object" ? Object.keys(payload) : [];
  line.claims = names.filter((n) => n.length <= 64).sort().slice(0, 50);
  return line;
}

/**
 * The link check's HTTP server. Logs only fixed fields, never an error's text.
 * @param {{ verifier: { verify(c: string): Promise<object> }, decide: typeof realDecide, graph: object, github: object, zitadel: object, log: (line: object) => void }} deps
 * @returns {http.Server}
 */
export function createServer({ verifier, decide, graph, github, zitadel, log }) {
  const send = (res, status, type, body) => {
    res.writeHead(status, type ? { "Content-Type": type } : {});
    res.end(body);
  };

  async function call(req, res, url) {
    let body;
    try {
      body = await readBody(req);
    } catch (e) {
      if (e instanceof TooLarge) {
        res.writeHead(413, { Connection: "close" });
        res.end();
        return;
      }
      throw e;
    }
    let payload;
    try {
      payload = await verifier.verify(body);
    } catch (e) {
      if (e instanceof JwtError) {
        log({ outcome: "bad-jwt", reason: REASONS.has(e.reason) ? e.reason : "malformed" });
        send(res, 401);
        return;
      }
      throw e;
    }
    log(claimsLine(body, payload));
    const response = payload?.response;
    if (payload?.fullMethod !== RETRIEVE_INTENT_METHOD || response === null || typeof response !== "object") {
      log({ outcome: "bad-payload" });
      send(res, 400);
      return;
    }
    const ids = {
      googleIdpId: url.searchParams.get("google") ?? "",
      microsoftIdpId: url.searchParams.get("microsoft") ?? "",
      githubIdpId: url.searchParams.get("github") ?? "",
    };
    const result = await decide(response, ids, { graph, github, zitadel, log });
    send(res, 200, "application/json", JSON.stringify(result));
  }

  return http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, "http://localhost");
      if (req.method === "GET" && url.pathname === "/link-check/health") {
        send(res, 200, "text/plain", "ok");
      } else if (req.method === "POST" && url.pathname === "/link-check/call") {
        await call(req, res, url);
      } else {
        send(res, 404);
      }
    } catch {
      log({ outcome: "server-error" });
      if (!res.headersSent) send(res, 500);
      else res.end();
    }
  });
}

function parseKey(raw) {
  try {
    const key = JSON.parse(raw ?? "");
    return key && typeof key.keyId === "string" && typeof key.key === "string" && typeof key.userId === "string" ? key : null;
  } catch {
    return null;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const issuer = process.env.ISSUER;
  if (!issuer) {
    console.log(JSON.stringify({ outcome: "no-issuer" }));
    process.exit(1);
  }
  const key = parseKey(process.env.LINK_CHECK_KEY);
  const log = (line) => console.log(JSON.stringify(line));
  log({ outcome: "start", key: key !== null });
  const server = createServer({
    verifier: jwtVerifier({ issuer }),
    decide: realDecide,
    graph: graphClient(),
    github: githubClient(),
    zitadel: zitadelClient({ issuer, key }),
    log,
  });
  server.listen(Number(process.env.PORT) || 8080);
}

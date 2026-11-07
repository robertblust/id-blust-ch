"""Links a provider's account to a user who already signs in another way, the one link ZITADEL's
login v2 cannot make for such a user, as the README's step 26 says. It signs in to id.blust.ch as
the machine user terraform, with the JSON key read on stdin, for one five-minute token, and prints
neither the key nor the token. It needs Python 3 and openssl and nothing else.

    K='gcloud secrets versions access latest --secret zitadel-admin-key --project blust-ch-mcp'
    $K | python3 -I zitadel/link-idp.py pending
    $K | python3 -I zitadel/link-idp.py link <user id> <provider id> <external id> <external name>
    $K | python3 -I zitadel/link-idp.py links <user id>

pending lists the users and the providers, and every recent sign-in at a provider that ZITADEL
matched to no user, with the external id and name the provider gave. A person who wants to add
Microsoft presses its button once, ends on the account-not-found page, and their attempt is then
the newest unmatched one with their address as its name. link joins that external account to the
user, and links lists a user's links to check it.
"""
import base64
import json
import os
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

ISSUER = "https://id.blust.ch"

# python.org's Python for macOS ships no certificates of its own; the system's bundle serves.
_cafile = "/etc/ssl/cert.pem" if os.path.exists("/etc/ssl/cert.pem") else None
urllib.request.install_opener(
    urllib.request.build_opener(urllib.request.HTTPSHandler(context=ssl.create_default_context(cafile=_cafile)))
)


def _b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def token(key):
    """Exchanges a JWT signed with the machine key for an access token to ZITADEL's own APIs."""
    now = int(time.time())
    header = {"alg": "RS256", "kid": key["keyId"]}
    claims = {"iss": key["userId"], "sub": key["userId"], "aud": ISSUER, "iat": now, "exp": now + 300}
    signing_input = (_b64(json.dumps(header).encode()) + "." + _b64(json.dumps(claims).encode())).encode()
    fd, path = tempfile.mkstemp()
    try:
        os.write(fd, key["key"].encode())
        os.close(fd)
        signature = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", path], input=signing_input, capture_output=True, check=True
        ).stdout
    finally:
        os.remove(path)
    body = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "scope": "openid urn:zitadel:iam:org:project:id:zitadel:aud",
        "assertion": signing_input.decode() + "." + _b64(signature),
    }).encode()
    with urllib.request.urlopen(urllib.request.Request(ISSUER + "/oauth/v2/token", data=body)) as r:
        return json.load(r)["access_token"]


def call(tok, path, body):
    request = urllib.request.Request(
        ISSUER + path, method="POST", data=json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit("HTTP %d from %s: %s" % (e.code, path, e.read().decode()[:500]))


def events(tok, event_type):
    return call(tok, "/admin/v1/events/_search", {"event_types": [event_type], "asc": False, "limit": 50}).get("events", [])


def pending(tok):
    providers = {p["id"]: p.get("name") for p in call(tok, "/admin/v1/idps/templates/_search", {}).get("result", [])}
    print("providers:")
    for pid, name in providers.items():
        print("  %s  %s" % (pid, name))
    print("users:")
    for u in call(tok, "/v2/users", {"queries": [{"typeQuery": {"type": "TYPE_HUMAN"}}]}).get("result", []):
        print("  %s  %s" % (u["userId"], u.get("preferredLoginName")))
    # An attempt's provider is on its started event, and what the provider said on its succeeded
    # event; both belong to the intent, the events' aggregate.
    started = {e["aggregate"]["id"]: e.get("payload", {}).get("idpId") for e in events(tok, "idpintent.started")}
    print("sign-ins at a provider that matched no user, newest first:")
    for e in events(tok, "idpintent.succeeded"):
        p = e.get("payload", {})
        if p.get("userId"):
            continue
        pid = started.get(e["aggregate"]["id"])
        print("  %s  provider %s (%s)  external id %s  external name %s" % (
            e.get("creationDate"), pid, providers.get(pid, "?"), p.get("idpUserId"), p.get("idpUserName")))


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("pending", "link", "links"):
        sys.exit(__doc__)
    tok = token(json.loads(sys.stdin.read()))
    action, args = sys.argv[1], sys.argv[2:]
    if action == "pending":
        pending(tok)
    elif action == "link":
        user_id, provider_id, external_id, external_name = args
        call(tok, "/v2/users/%s/links" % user_id,
             {"idpLink": {"idpId": provider_id, "userId": external_id, "userName": external_name}})
        print("linked")
    elif action == "links":
        (user_id,) = args
        for link in call(tok, "/v2/users/%s/links/_search" % user_id, {}).get("result", []):
            print("  provider %s  external id %s  external name %s" % (link.get("idpId"), link.get("userId"), link.get("userName")))


if __name__ == "__main__":
    main()

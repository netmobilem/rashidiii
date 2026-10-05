# Security policy

## Supported versions

Security fixes are applied to the latest release line (`1.x`). Deployments older than the
current `main` should upgrade with `./scripts/upgrade.sh` (it takes a verified backup first).

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

* Preferred: GitHub → **Security** tab → **Report a vulnerability** (private advisory).
* Or e-mail the maintainer listed in the repository profile with:
  * affected component (panel API, node agent, installer, container images),
  * version/commit, and a minimal reproduction,
  * the impact you believe it has.

You can expect an acknowledgement within **72 hours** and a fix or mitigation plan within
**14 days** for confirmed reports. Please give us a reasonable window to release a fix
before public disclosure — we will credit you in the advisory unless you prefer otherwise.

## In scope

* Authentication/authorisation bypass (JWT, cookie, API key scopes, RBAC).
* Node channel attacks: token leakage, replay of signed requests, HMAC bypass.
* Subscription token enumeration or data exposure outside `/sub/<token>`.
* Injection (SQL, command, template), SSRF, path traversal.
* Secret exposure: repository, images, logs, API responses, backups.
* Privilege escalation through the agent's `/agent/v1/*` surface.

## Out of scope

* Findings that require an already-compromised host, database or `secrets.env`.
* Missing hardening headers on non-production (`ENV=development`) deployments.
* Reports from automated scanners without a reproducible impact.
* Denial of service through raw volume of traffic (rate limiting exists; capacity is the
  operator's responsibility).

## Hardening checklist for operators

See [`docs/SECURITY.md`](docs/SECURITY.md). The short version:

- [ ] `ENV=production`, HTTPS public URL, `PUBLIC_URL` set.
- [ ] Strong `BOOTSTRAP_ADMIN_PASSWORD` (or rotate the generated one immediately).
- [ ] `CORS_ORIGINS` restricted to your panel origin.
- [ ] Node agent ports firewalled to the panel, or fronted by TLS.
- [ ] `secrets.env` and the newest database backup stored off-host.
- [ ] Secret scanning + push protection enabled on the repository.

## Design guarantees

* No default credentials ship with the project; the first owner password is either
  operator-supplied or randomly generated and printed once.
* Node tokens are stored hashed (lookup) and sealed (for panel→node pushes); the raw token
  is shown exactly once, at creation time.
* Every write is audited (`activities`) and authentication events are logged (`logs`).
* Automatic recovery is bounded (`SELF_HEAL_MAX_ATTEMPTS`) with exponential backoff, so a
  failing node can never turn into an infinite retry loop.

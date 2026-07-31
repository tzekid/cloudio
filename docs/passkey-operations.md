# Passkey operations

Cloudio has one interactive authentication mechanism: WebAuthn passkeys with
user verification. There is no password, bearer token, TOTP, email recovery,
or permanently open registration route.

## Production configuration

Set the final public origin and RP ID before enrolling the first credential.
Changing either value invalidates existing passkeys.

```toml
[auth]
origin = "https://cloudio.example.com"
rp_id = "cloudio.example.com"
```

Equivalent environment variables are `CLOUDIO_AUTH_ORIGIN` and
`CLOUDIO_AUTH_RP_ID`. The origin has no trailing slash. The RP ID is a hostname,
not a URL or host/port pair. Non-loopback HTTP origins are rejected.

The application should listen on loopback behind an HTTPS proxy. When bound to
loopback, Cloudio may use the proxy-provided first `X-Forwarded-For` address for
per-client authentication limits; an independent global ceiling is always
applied.

## Initial enrollment

Run on the host:

```sh
cloudio auth status
cloudio auth bootstrap --ttl 10m
```

The second command prints one URL. Treat it like a short-lived secret:

- do not paste it into chat, tickets, logs, or shell history
- open it directly in the browser that will create the passkey
- complete enrollment before its expiry

The token is carried in the URL fragment, removed from browser history before
the first network request, and sent only in `X-Cloudio-Bootstrap` over the
configured origin. SQLite stores its SHA-256 hash, never the token.

Touch ID, Face ID, a device passcode, a synced passkey provider, and compatible
hardware keys are supported. Registration requires discoverable credentials
and user verification. Attestation is disabled.

After enrollment:

```sh
cloudio auth status
```

The result should report `configured=yes`, at least one credential, an active
session, and no active bootstrap authorization.

## Normal use

`/login.html` offers passkey sign-in. `/security.html` can:

- list active passkeys without exposing public keys
- create an additional passkey
- rename a passkey
- revoke a passkey
- sign out the current session

Cloudio refuses to revoke the last active passkey. Register a second passkey on
a different device or a hardware security key before it is needed.

Sessions last 12 hours and are server-side revocable. The browser receives a
host-only `__Host-cloudio_session` cookie with `Secure`, `HttpOnly`,
`SameSite=Strict`, and `Path=/`. Unsafe requests additionally require exact
`Origin` and a session-bound `X-Cloudio-CSRF` token.

The separate `__Host-cloudio_theme` preference cookie is not authentication
state. It is host-only, `Secure`, `HttpOnly`, and `SameSite=Strict`, and remains
in the browser when the session is cleared so the login page keeps the chosen
appearance.

## Lost-all-passkeys recovery

Recovery requires shell access and a new backup path:

```sh
cloudio auth reset \
  --backup .cloudio/backups/before-auth-reset-YYYYMMDD-HHMMSS.db \
  --confirm
cloudio auth bootstrap --ttl 10m
```

Reset is refused without `--confirm` and a path that does not already exist.
Cloudio creates an online SQLite backup, verifies it, then removes credentials,
sessions, pending challenges, and bootstrap state. Reset does not create a
setup window by itself.

Keep the backup with mode `0600`. Restore is an operator database-recovery
operation and is intentionally not exposed over HTTP.

## Verification checklist

After a deployment or proxy change:

1. Anonymous `/` redirects to `/login.html`.
2. Anonymous private API and unknown API paths both return `401`.
3. Login CSS, passkey adapter, and login JavaScript load; application assets do
   not load anonymously.
4. Login invokes the intended authenticator and reaches the dashboard.
5. A mutation without `Origin` or `X-Cloudio-CSRF` returns `403`.
6. Logout clears the cookie and the old cookie no longer authorizes requests.
7. The proxy adds HSTS at the HTTPS boundary.
8. `cloudio auth status` reports the expected credential/session counts.

Never log WebAuthn payloads, challenges, session/CSRF/bootstrap tokens,
signatures, credential public keys, or the complete one-use setup URL.

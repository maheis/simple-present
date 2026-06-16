# SimplePresent sync server (minimal scaffold)

Minimal Go scaffold for a Linux-only headless sync server using SQLite and JSON config.

Security features included in the scaffold:

- HTTPS enforcement via TLS or trusted reverse-proxy headers
- JWT device tokens returned by `/pair`
- Device revocation endpoint at `/devices/{id}/revoke`
- In-memory rate limiting per IP and per account
- Per-account quotas for devices, active items and stored payload bytes

Pairing model (server never stores word phrase):

- First client creates/selects 9-word phrase locally.
- Client derives a pairing keypair locally and sends only the base64 public key in `/register` as `pairing_public_key`.
- Additional client asks `/pair/challenge` and signs `simplepresent-pair|account_id|challenge_id|device_name` with the phrase-derived private key.
- Server verifies signature with stored public key and creates a device token.
- Server never stores phrase plaintext or phrase hash.

## Reverse proxy setup (Apache)

When running behind a reverse proxy that terminates TLS (e.g. Apache with a valid Let's Encrypt certificate), set `require_tls: true` and `trust_proxy_headers: true` in your config. The server binds plain HTTP locally; the proxy forwards HTTPS traffic.

For this to work, Apache **must** set `X-Forwarded-Proto: https` — otherwise the server returns `426 Upgrade Required`.

Minimal Apache VirtualHost snippet:

```apache
<VirtualHost *:443>
    # ... SSL config ...

    # Required: tell the backend it was reached via HTTPS
    RequestHeader set X-Forwarded-Proto "https"

    ProxyPass / http://127.0.0.1:7443/
    ProxyPassReverse / http://127.0.0.1:7443/
</VirtualHost>
```

Make sure `mod_headers` and `mod_proxy` are enabled:

```bash
sudo a2enmod headers proxy proxy_http
sudo systemctl reload apache2
```

Example `config.json` for this setup:

```json
{
  "bind": "127.0.0.1:7443",
  "database_path": "./simplepresent.db",
  "tls": { "enabled": false },
  "security": {
    "require_tls": true,
    "trust_proxy_headers": true,
    "jwt_secret": "change-me-in-production"
  }
}
```

## Account policy and admin alerts

`security.account_policy` controls registration capacity, inactivity archive policy,
and alert mails:

- `max_accounts`: maximum number of active (not archived) accounts
- `admin_email`: recipient for capacity alerts (75/90/100%)
- `archive_after_days`: archive account after this many inactive days
- `warning_days`: app warning thresholds (default 14/7)
- `sweep_interval_minutes`: archive sweep interval
- `smtp`: SMTP settings used for admin mails

Environment variables can override these values at runtime:

- `SIMPLEPRESENT_MAX_ACCOUNTS`
- `SIMPLEPRESENT_ADMIN_EMAIL`
- `SIMPLEPRESENT_ARCHIVE_AFTER_DAYS`
- `SIMPLEPRESENT_ARCHIVE_WARNING_DAYS` (comma separated, e.g. `14,7`)
- `SIMPLEPRESENT_SWEEP_INTERVAL_MINUTES`
- `SIMPLEPRESENT_SMTP_HOST`
- `SIMPLEPRESENT_SMTP_PORT`
- `SIMPLEPRESENT_SMTP_USERNAME`
- `SIMPLEPRESENT_SMTP_PASSWORD`
- `SIMPLEPRESENT_SMTP_FROM`

Quick start:

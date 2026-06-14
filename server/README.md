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

Quick start:

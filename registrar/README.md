# MentionMate Registrar

Admin-facing service that lets team members self-register for MentionMate:
it runs their Telegram OTP login and launches their own MentionMate
container. See `docs/superpowers/specs/2026-07-09-team-rollout-design.md`
in the repo root for the full design rationale.

## Deploy

1. Create the shared alert bot once via @BotFather, note its token.
2. Copy `.env.example` to `.env` here and fill in `TG_BOT_TOKEN` (and
   optionally `REGISTRAR_STAGGER_SECONDS`, default 600 = 10 minutes).
3. `docker compose up -d --build`.
4. Point your internal-only reverse proxy / VPN at `127.0.0.1:8000` on
   this VPS. **Do not expose this port publicly** — it drives Telegram
   OTP/2FA login for personal accounts.

## Security requirements (do not skip)

- Internal/VPN-only access. The compose file binds to `127.0.0.1` only —
  keep it that way.
- TLS terminated at your internal reverse proxy, even for internal traffic.
- `/var/run/docker.sock` is mounted into this container, which is
  effectively root-equivalent access to the host. Only the admin should
  have shell access to this VPS.
- `registrar-data/<username>/` holds each user's Telethon session — treat
  it as at least as sensitive as an SSH private key.

## Rollout for team members

Send them: `https://<your-internal-host>/register` and the two prerequisite
steps (create their own app at my.telegram.org, then follow the 3-page
wizard). Registrations are automatically spaced out
(`REGISTRAR_STAGGER_SECONDS`) so simultaneous sign-ups don't create a burst
of new sessions from this VPS's IP.

# MentionMate Registrar

Admin-facing service that lets team members self-register for MentionMate:
it runs their Telegram OTP login and launches their own MentionMate
container. See `docs/superpowers/specs/2026-07-09-team-rollout-design.md`
in the repo root for the full design rationale.

## Deploy

1. Create the shared alert bot once via @BotFather, note its token.
2. Create a `.env` file here with:
   ```
   TG_BOT_TOKEN=<your bot token>
   REGISTRAR_HOST_DATA_ROOT=<absolute HOST path of this registrar/ dir>/registrar-data
   # optional, default 600 = 10 minutes:
   REGISTRAR_STAGGER_SECONDS=600
   ```
   `REGISTRAR_HOST_DATA_ROOT` is **required** and easy to get wrong: it
   must be the real path on the VPS's own filesystem (e.g.
   `/home/youruser/mention-mate/registrar/registrar-data`), NOT
   `/app/registrar-data` (that's only how this container sees it). The
   registrar talks to the host's Docker daemon over the mounted
   `docker.sock` to launch each user's container (Docker-outside-of-Docker),
   and that daemon resolves bind-mount paths against the HOST filesystem —
   getting this wrong silently mounts the wrong directory into the new
   container, which then fails with
   `sqlite3.OperationalError: unable to open database file`.
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

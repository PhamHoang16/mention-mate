"""FastAPI app tying together the registration flow.

Route summary (finalized in Task 8):
- POST /register/start    — collect phone/api_id/api_hash/username, send OTP
- POST /register/verify   — complete login with the OTP code (+2FA password)
- POST /register/finalize — resolve chat_id, write .env, launch the container
"""
import asyncio
import logging
import os
import secrets
import time
from pathlib import Path

import aiohttp
from fastapi import BackgroundTasks, FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel

from registrar.chat_id_resolver import ChatIdNotFoundError, resolve_chat_id
from registrar.env_writer import build_env, write_user_env_file
from registrar.orchestrator import Orchestrator
from registrar.queue import StaggerQueue
from registrar.store import RegistrationStore
from registrar.telegram_login import TwoFactorRequired, complete_login, start_login

logger = logging.getLogger(__name__)

# In-memory, short-lived state between /register/start and /register/verify —
# deliberately not persisted: if the registrar restarts mid-registration, the
# user just starts over from /register/start.
PENDING: dict[str, dict] = {}

# How long an abandoned PENDING entry (phone/api_hash/phone_code_hash sitting
# in memory because the user never finished /register/verify+finalize) is
# kept before being swept away on the next /register/start call.
PENDING_TTL_SECONDS = 3600


def _sweep_expired_pending() -> None:
    now = time.monotonic()
    expired = [
        username
        for username, pending in PENDING.items()
        if now - pending.get("created_at", now) > PENDING_TTL_SECONDS
    ]
    for username in expired:
        del PENDING[username]


class RegisterStartRequest(BaseModel):
    phone: str
    api_id: int
    api_hash: str
    username: str


class RegisterVerifyRequest(BaseModel):
    username: str
    code: str
    password: str | None = None


class RegisterFinalizeRequest(BaseModel):
    username: str


def _session_path(data_root: str, username: str) -> str:
    return os.path.join(data_root, username, "mentions_session")


async def send_confirmation(session, bot_token: str, chat_id: int) -> None:
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    payload = {"chat_id": chat_id, "text": "✅ Your MentionMate is now running. You're all set!"}
    async with session.post(url, json=payload) as resp:
        data = await resp.json()
        if not data.get("ok"):
            raise RuntimeError(f"Bot API error sending confirmation: {data}")


def create_app(
    bot_token: str,
    data_root: str,
    registrations_path: str,
    docker_client,
    image: str,
    stagger_seconds: int,
) -> FastAPI:
    app = FastAPI(title="MentionMate Registrar")
    templates = Jinja2Templates(directory=str(Path(__file__).parent / "templates"))
    app.state.bot_token = bot_token
    app.state.data_root = data_root
    app.state.store = RegistrationStore(registrations_path)
    app.state.docker_client = docker_client
    app.state.image = image
    app.state.stagger_seconds = stagger_seconds
    app.state.orchestrator = Orchestrator(client=docker_client, image=image)
    app.state.queue = StaggerQueue(min_interval_seconds=stagger_seconds)

    @app.post("/register/start")
    async def register_start(req: RegisterStartRequest):
        _sweep_expired_pending()
        phone_code_hash = await start_login(
            api_id=req.api_id,
            api_hash=req.api_hash,
            session_path=_session_path(data_root, req.username),
            phone=req.phone,
        )
        PENDING[req.username] = {
            "phone": req.phone,
            "api_id": req.api_id,
            "api_hash": req.api_hash,
            "phone_code_hash": phone_code_hash,
            "nonce": secrets.token_urlsafe(8),
            "created_at": time.monotonic(),
        }
        return {"status": "code_sent"}

    @app.post("/register/verify")
    async def register_verify(req: RegisterVerifyRequest):
        pending = PENDING.get(req.username)
        if pending is None:
            raise HTTPException(status_code=404, detail="no_pending_registration")

        try:
            await complete_login(
                api_id=pending["api_id"],
                api_hash=pending["api_hash"],
                session_path=_session_path(data_root, req.username),
                phone=pending["phone"],
                code=req.code,
                phone_code_hash=pending["phone_code_hash"],
                password=req.password,
            )
        except TwoFactorRequired:
            raise HTTPException(status_code=400, detail="two_factor_required")

        pending["logged_in"] = True
        return {"status": "logged_in"}

    async def _finalize_in_background(username: str, env: dict, user_data_dir: str, chat_id: int) -> None:
        """Runs the staggered container launch + best-effort confirmation DM
        + store/PENDING bookkeeping outside the request/response cycle, so
        /register/finalize doesn't hold the HTTP connection open for up to
        `stagger_seconds` (see Fix 2). The synchronous Docker SDK call is
        pushed to a worker thread so it never blocks the event loop either.
        """

        async def launch():
            return await asyncio.to_thread(app.state.orchestrator.start_user_container, username, env, user_data_dir)

        await app.state.queue.run(launch)

        try:
            async with aiohttp.ClientSession() as confirm_session:
                await send_confirmation(confirm_session, bot_token=bot_token, chat_id=chat_id)
        except Exception:
            # Best-effort: the container is already running, which is what
            # matters (Fix 3). Don't surface the underlying exception content
            # here — it can embed the bot-token URL — just note the failure.
            logger.warning("confirmation DM delivery failed for username=%s", username)

        await app.state.store.set(username, {"status": "active", "chat_id": chat_id})
        PENDING.pop(username, None)

    @app.post("/register/finalize", status_code=202)
    async def register_finalize(req: RegisterFinalizeRequest, background_tasks: BackgroundTasks):
        pending = PENDING.get(req.username)
        if pending is None or not pending.get("logged_in"):
            raise HTTPException(status_code=404, detail="login_not_completed")

        async with aiohttp.ClientSession() as session:
            try:
                chat_id = await resolve_chat_id(session, bot_token=bot_token, nonce=pending["nonce"])
            except ChatIdNotFoundError:
                raise HTTPException(status_code=409, detail="chat_id_not_found")

        env = build_env(
            bot_token=bot_token,
            api_id=pending["api_id"],
            api_hash=pending["api_hash"],
            username=req.username,
            alert_chat_id=chat_id,
        )
        write_user_env_file(data_root, req.username, env)
        user_data_dir = os.path.join(data_root, req.username)

        background_tasks.add_task(_finalize_in_background, req.username, env, user_data_dir, chat_id)
        return {"status": "queued"}

    @app.get("/register", response_class=HTMLResponse)
    async def register_page(request: Request):
        return templates.TemplateResponse(request, "register_start.html", {})

    @app.get("/register/verify-page", response_class=HTMLResponse)
    async def register_verify_page(request: Request, username: str):
        return templates.TemplateResponse(request, "register_verify.html", {"username": username})

    @app.get("/register/finalize-page", response_class=HTMLResponse)
    async def register_finalize_page(request: Request, username: str):
        pending = PENDING.get(username)
        nonce = pending["nonce"] if pending else ""
        return templates.TemplateResponse(request, "register_finalize.html", {"username": username, "nonce": nonce})

    return app


# Module-level app for `uvicorn registrar.app:app`, wired from env vars.
def _build_app_from_env():
    from docker import DockerClient
    from registrar.config import load_settings

    settings = load_settings()
    return create_app(
        bot_token=settings.bot_token,
        data_root=settings.data_root,
        registrations_path=settings.registrations_path,
        docker_client=DockerClient(base_url="unix://var/run/docker.sock"),
        image=settings.image,
        stagger_seconds=settings.stagger_seconds,
    )


app = _build_app_from_env()

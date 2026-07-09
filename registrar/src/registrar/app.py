"""FastAPI app tying together the registration flow.

Route summary (finalized in Task 8):
- POST /register/start    — collect phone/api_id/api_hash/username, send OTP
- POST /register/verify   — complete login with the OTP code (+2FA password)
- POST /register/finalize — resolve chat_id, write .env, launch the container
"""
import os

import aiohttp
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from registrar.chat_id_resolver import ChatIdNotFoundError, resolve_chat_id
from registrar.env_writer import build_env, write_user_env_file
from registrar.orchestrator import Orchestrator
from registrar.queue import StaggerQueue
from registrar.store import RegistrationStore
from registrar.telegram_login import TwoFactorRequired, complete_login, start_login

# In-memory, short-lived state between /register/start and /register/verify —
# deliberately not persisted: if the registrar restarts mid-registration, the
# user just starts over from /register/start.
PENDING: dict[str, dict] = {}


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

    @app.post("/register/finalize")
    async def register_finalize(req: RegisterFinalizeRequest):
        pending = PENDING.get(req.username)
        if pending is None or not pending.get("logged_in"):
            raise HTTPException(status_code=404, detail="login_not_completed")

        async with aiohttp.ClientSession() as session:
            try:
                chat_id = await resolve_chat_id(session, bot_token=bot_token)
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

        async def launch():
            return app.state.orchestrator.start_user_container(req.username, env, user_data_dir)

        container_id = await app.state.queue.run(launch)

        async with aiohttp.ClientSession() as confirm_session:
            await send_confirmation(confirm_session, bot_token=bot_token, chat_id=chat_id)

        await app.state.store.set(req.username, {"status": "active", "chat_id": chat_id})
        del PENDING[req.username]
        return {"status": "active", "container_id": container_id}

    return app

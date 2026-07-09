"""FastAPI app tying together the registration flow.

Route summary (finalized in Task 8):
- POST /register/start    — collect phone/api_id/api_hash/username, send OTP
- POST /register/verify   — complete login with the OTP code (+2FA password)
- POST /register/finalize — resolve chat_id, write .env, launch the container
"""
import os

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

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


def _session_path(data_root: str, username: str) -> str:
    return os.path.join(data_root, username, "mentions_session")


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

    return app

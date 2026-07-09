import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    bot_token: str
    data_root: str
    registrations_path: str
    stagger_seconds: int
    image: str


def load_settings() -> Settings:
    try:
        bot_token = os.environ["TG_BOT_TOKEN"]
    except KeyError as e:
        raise RuntimeError(f"Missing required environment variable: {e}") from e
    data_root = os.environ.get("REGISTRAR_DATA_ROOT", "/app/registrar-data")
    return Settings(
        bot_token=bot_token,
        data_root=data_root,
        registrations_path=os.environ.get(
            "REGISTRAR_STATE_PATH", os.path.join(data_root, "registrations.json")
        ),
        stagger_seconds=int(os.environ.get("REGISTRAR_STAGGER_SECONDS", "600")),
        image=os.environ.get("REGISTRAR_IMAGE", "ghcr.io/phamhoang16/mention-mate:latest"),
    )

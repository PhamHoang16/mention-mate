import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    bot_token: str
    data_root: str
    host_data_root: str
    registrations_path: str
    stagger_seconds: int
    image: str


def load_settings() -> Settings:
    try:
        bot_token = os.environ["TG_BOT_TOKEN"]
    except KeyError as e:
        raise RuntimeError(f"Missing required environment variable: {e}") from e
    data_root = os.environ.get("REGISTRAR_DATA_ROOT", "/app/registrar-data")
    try:
        host_data_root = os.environ["REGISTRAR_HOST_DATA_ROOT"]
    except KeyError as e:
        # This MUST be the real host filesystem path of the ./registrar-data
        # bind mount (see docker-compose.yml), NOT the in-container path
        # above. The registrar talks to the HOST's Docker daemon over the
        # mounted docker.sock (Docker-outside-of-Docker) to launch per-user
        # containers — any bind-mount source path it hands the Docker API is
        # resolved against the HOST filesystem, not this container's own
        # namespace. Passing the in-container path here silently mounts the
        # wrong (often nonexistent) directory into the new container, and
        # its MentionMate process then fails with
        # "sqlite3.OperationalError: unable to open database file" because
        # the just-written Telethon session isn't where it's looking.
        raise RuntimeError(
            "Missing required environment variable: 'REGISTRAR_HOST_DATA_ROOT' "
            "(the absolute HOST path of the ./registrar-data directory, e.g. "
            "/home/youruser/mention-mate/registrar/registrar-data — see README.md)"
        ) from e
    return Settings(
        bot_token=bot_token,
        data_root=data_root,
        host_data_root=host_data_root,
        registrations_path=os.environ.get(
            "REGISTRAR_STATE_PATH", os.path.join(data_root, "registrations.json")
        ),
        stagger_seconds=int(os.environ.get("REGISTRAR_STAGGER_SECONDS", "600")),
        image=os.environ.get("REGISTRAR_IMAGE", "ghcr.io/phamhoang16/mention-mate:latest"),
    )

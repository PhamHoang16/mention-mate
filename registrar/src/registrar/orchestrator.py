"""Spins up / tears down per-user MentionMate containers via the Docker SDK.

Requires the registrar container to have /var/run/docker.sock mounted
(Docker-outside-of-Docker) — see registrar/README.md for the security note
on why this must stay internal-only.
"""
import docker.errors
import docker.types


class Orchestrator:
    def __init__(self, client, image: str):
        self._client = client
        self._image = image

    def container_name(self, username: str) -> str:
        return f"mention-mate-{username}"

    def start_user_container(self, username: str, env: dict[str, str], data_dir: str) -> str:
        name = self.container_name(username)
        self._remove_if_exists(name)
        container = self._client.containers.run(
            self._image,
            name=name,
            detach=True,
            restart_policy={"Name": "unless-stopped"},
            environment=env,
            volumes={data_dir: {"bind": "/app/data", "mode": "rw"}},
            log_config=docker.types.LogConfig(type="json-file", config={"max-size": "10m", "max-file": "3"}),
        )
        return container.id

    def stop_user_container(self, username: str) -> None:
        self._remove_if_exists(self.container_name(username))

    def _remove_if_exists(self, name: str) -> None:
        try:
            existing = self._client.containers.get(name)
        except docker.errors.NotFound:
            return
        existing.remove(force=True)

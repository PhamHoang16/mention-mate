from unittest.mock import MagicMock

import docker.errors

from registrar.orchestrator import Orchestrator


def test_container_name_is_prefixed_with_username():
    orchestrator = Orchestrator(client=MagicMock(), image="ghcr.io/phamhoang16/mention-mate:latest")
    assert orchestrator.container_name("hoangp47") == "mention-mate-hoangp47"


def test_start_user_container_runs_with_expected_kwargs(tmp_path):
    client = MagicMock()
    client.containers.get.side_effect = docker.errors.NotFound("no such container")
    client.containers.run.return_value = MagicMock(id="abc123")
    orchestrator = Orchestrator(client=client, image="ghcr.io/phamhoang16/mention-mate:latest")
    env = {"TG_API_ID": "555", "TG_MY_USERNAME": "hoangp47"}
    data_dir = str(tmp_path / "hoangp47")

    container_id = orchestrator.start_user_container("hoangp47", env, data_dir)

    assert container_id == "abc123"
    client.containers.run.assert_called_once_with(
        "ghcr.io/phamhoang16/mention-mate:latest",
        name="mention-mate-hoangp47",
        detach=True,
        restart_policy={"Name": "unless-stopped"},
        environment=env,
        volumes={data_dir: {"bind": "/app/data", "mode": "rw"}},
        log_config=docker.types.LogConfig(type="json-file", config={"max-size": "10m", "max-file": "3"}),
    )


def test_start_user_container_removes_existing_container_first(tmp_path):
    client = MagicMock()
    existing = MagicMock()
    client.containers.get.return_value = existing
    client.containers.run.return_value = MagicMock(id="new-id")
    orchestrator = Orchestrator(client=client, image="ghcr.io/phamhoang16/mention-mate:latest")

    orchestrator.start_user_container("hoangp47", {}, str(tmp_path))

    existing.remove.assert_called_once_with(force=True)


def test_stop_user_container_removes_when_present():
    client = MagicMock()
    existing = MagicMock()
    client.containers.get.return_value = existing
    orchestrator = Orchestrator(client=client, image="ghcr.io/phamhoang16/mention-mate:latest")

    orchestrator.stop_user_container("hoangp47")

    client.containers.get.assert_called_once_with("mention-mate-hoangp47")
    existing.remove.assert_called_once_with(force=True)


def test_stop_user_container_is_a_noop_when_absent():
    client = MagicMock()
    client.containers.get.side_effect = docker.errors.NotFound("no such container")
    orchestrator = Orchestrator(client=client, image="ghcr.io/phamhoang16/mention-mate:latest")

    orchestrator.stop_user_container("hoangp47")  # must not raise

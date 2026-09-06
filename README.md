# expert.chat appliance

This repository contains the two-container local installation for expert.chat. It starts the application and PostgreSQL, creates the installation secrets automatically, stores data in Docker named volumes and exposes the application only on `127.0.0.1:4000` by default.

## Install a specific release

Install [Docker](https://docs.docker.com/get-docker/) with Docker Compose, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.1.2/compose.yaml | docker compose -p expert-chat -f - up -d
```

Open <http://localhost:4000> when the application becomes ready. The first release may take a few minutes to download and prepare its database. To claim a new appliance, setup asks for a Resend API key and verified sender so that email-code login will work; it stores the key encrypted and never returns it through the API. Sentry remains optional.

Release `v0.1.2` supports `linux/amd64`. Apple Silicon support will return before v1 after native acceptance testing; do not force this amd64-only release onto an arm64 computer.

## Operate the installation

Show its state and recent logs:

```bash
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.1.2/compose.yaml | docker compose -p expert-chat -f - ps
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.1.2/compose.yaml | docker compose -p expert-chat -f - logs --tail 100
```

Stop and later restart the containers without removing saved data:

```bash
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.1.2/compose.yaml | docker compose -p expert-chat -f - stop
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.1.2/compose.yaml | docker compose -p expert-chat -f - start
```

Set `EXPERT_CHAT_PORT` on the Compose side of the pipe if port 4000 is already occupied. For example, `curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.1.2/compose.yaml | EXPERT_CHAT_PORT=4080 docker compose -p expert-chat -f - up -d` exposes the application at <http://localhost:4080>.

The reviewed `stable` channel will be documented after this release passes the clean-install, persistence, recovery and resource acceptance exercises. Version tags never move and remain the reproducible installation contract.

Do not run `down --volumes` unless you deliberately want to remove the PostgreSQL data and the installation secrets. The full backup, restore, update, rollback and removal procedures will be published after their acceptance exercises pass.

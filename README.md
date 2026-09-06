# expert.chat appliance

This repository contains the two-container local installation for expert.chat. It starts the application and PostgreSQL, creates the installation secrets automatically, stores data in Docker named volumes and exposes the application only on `127.0.0.1:4000` by default.

## Install a specific release

Install [Docker](https://docs.docker.com/get-docker/) with Docker Compose, then run:

```bash
docker compose -p expert-chat -f https://github.com/experts-chat/appliance.git@v0.1.0 up -d
```

Open <http://localhost:4000> when the application becomes ready. The first release may take a few minutes to download and prepare its database.

Release `v0.1.0` supports `linux/amd64`. Apple Silicon support will return before v1 after native acceptance testing; do not force this amd64-only release onto an arm64 computer.

## Operate the installation

Show its state and recent logs:

```bash
docker compose -p expert-chat -f https://github.com/experts-chat/appliance.git@v0.1.0 ps
docker compose -p expert-chat -f https://github.com/experts-chat/appliance.git@v0.1.0 logs --tail 100
```

Stop and later restart the containers without removing saved data:

```bash
docker compose -p expert-chat -f https://github.com/experts-chat/appliance.git@v0.1.0 stop
docker compose -p expert-chat -f https://github.com/experts-chat/appliance.git@v0.1.0 start
```

Set `EXPERT_CHAT_PORT` before the command if port 4000 is already occupied. For example, `EXPERT_CHAT_PORT=4080` exposes the application at <http://localhost:4080>.

The reviewed `stable` channel will be documented after this release passes the clean-install, persistence, recovery and resource acceptance exercises. Version tags never move and remain the reproducible installation contract.

Do not run `down --volumes` unless you deliberately want to remove the PostgreSQL data and the installation secrets. The full backup, restore, update, rollback and removal procedures will be published after their acceptance exercises pass.

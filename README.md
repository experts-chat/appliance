# expert.chat appliance

This repository contains the two-container local installation for expert.chat. It starts the application and PostgreSQL, creates the installation secrets automatically, stores data in Docker named volumes and exposes the application only on `127.0.0.1:4000` by default.

## Install

Install [Docker](https://docs.docker.com/get-docker/) with Docker Compose, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/stable/compose.yaml | docker compose -p expert-chat -f - up -d
```

Open <http://localhost:4000> when the application becomes ready. The first release may take a few minutes to download and prepare its database. To claim a new appliance, setup asks for a Resend API key and verified sender so that email-code login will work; it stores the key encrypted and never returns it through the API. Sentry remains optional. For an exactly reproducible install, replace `stable` with the immutable Compose release `v0.2.0`.

Release `v0.2.0` supports `linux/amd64`. Apple Silicon support will return before v1 after native acceptance testing; do not force this amd64-only release onto an arm64 computer.

## Operate the installation

Show its state and recent logs:

```bash
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.2.0/compose.yaml | docker compose -p expert-chat -f - ps
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.2.0/compose.yaml | docker compose -p expert-chat -f - logs --tail 100
```

Stop and later restart the containers without removing saved data:

```bash
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.2.0/compose.yaml | docker compose -p expert-chat -f - stop
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.2.0/compose.yaml | docker compose -p expert-chat -f - start
```

Set `EXPERT_CHAT_PORT` on the Compose side of the pipe if port 4000 is already occupied. For example, `curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.2.0/compose.yaml | EXPERT_CHAT_PORT=4080 docker compose -p expert-chat -f - up -d` exposes the application at <http://localhost:4080>.

The reviewed `stable` channel currently selects Compose release `v0.2.0`. It advances only after a candidate passes the clean-install, persistence, recovery and resource acceptance exercises. Version tags never move and remain the reproducible installation contract.

## Resource guidance

Make at least 2 GiB available to Docker for this pre-v1 appliance. On the amd64 acceptance host, the two services used about 569 MiB while idle and peaked at about 599 MiB during a deliberately small real Sync of 11 responses. The 2 GiB recommendation leaves operating headroom without imposing brittle per-container limits. It is not proof that a large initial Sync will fit: stage those collections in small batches and measure again before committing to a multi-day import.

The v1 release gate repeats this measurement on an Apple Silicon Mac with a native `linux/arm64` image and records the Docker Desktop allocation. The current amd64-only release must not be run through emulation as a substitute for that proof.

## Back up

Create a private backup directory and capture both PostgreSQL and the installation secrets:

```bash
backup_dir="expert-chat-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -m 0700 "$backup_dir"
docker exec expert-chat-db-1 pg_dump -U expert_chat -d expert_chat --format=custom > "$backup_dir/database.dump"
docker exec expert-chat-db-1 tar -C /run/expert-chat-secrets -czf - . > "$backup_dir/installation-secrets.tar.gz"
chmod 0600 "$backup_dir/database.dump" "$backup_dir/installation-secrets.tar.gz"
sha256sum "$backup_dir/database.dump" "$backup_dir/installation-secrets.tar.gz" > "$backup_dir/checksums.sha256"
```

The secret archive contains the keys that protect sessions and saved provider Credentials. Anyone who obtains it together with the database can decrypt those Credentials. Keep the directory private, copy it to storage you control, and encrypt it before sending it anywhere. Do not treat the database dump alone as a recoverable backup.

## Update and roll back

Take a backup first. To move to the currently accepted compatible release:

```bash
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/stable/compose.yaml | docker compose -p expert-chat -f - up -d
```

Compose downloads and recreates the application only when its pinned image changes. It leaves PostgreSQL and both named volumes in place. Check readiness and logs before continuing important work. Use the immutable `v0.2.0` URL instead when the exact release matters.

To return to the previous compatible release:

```bash
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.1.2/compose.yaml | docker compose -p expert-chat -f - up -d
```

A rollback is safe only when the release notes say the two versions are database-compatible. Restore the pre-update backup instead of forcing an older application across an incompatible schema change.

## Restore onto a clean installation

Put the backup directory on the replacement computer and verify it before starting anything:

```bash
backup_dir=/path/to/expert-chat-backup-YYYYMMDD-HHMMSS
(cd "$backup_dir" && sha256sum -c checksums.sha256)
```

Create the stopped containers and empty named volumes from the exact release you are restoring:

```bash
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.2.0/compose.yaml | docker compose -p expert-chat -f - create
```

Restore the generated secrets before PostgreSQL first starts:

```bash
docker run --rm --user 0 --entrypoint /bin/sh -i --volume expert-chat_installation-secrets:/restore postgres:18.6-trixie@sha256:4ef4dbc939d61acea57712655ddb4b4ab27419c913f94cca0cd57cb3ea3c2280 -ec 'tar -xzf - -C /restore' < "$backup_dir/installation-secrets.tar.gz"
```

Start PostgreSQL, wait until `docker inspect --format '{{.State.Health.Status}}' expert-chat-db-1` reports `healthy`, and restore the logical dump:

```bash
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.2.0/compose.yaml | docker compose -p expert-chat -f - start db
docker exec -i expert-chat-db-1 pg_restore -U expert_chat -d expert_chat --clean --if-exists --no-owner --no-privileges < "$backup_dir/database.dump"
```

Start the application and verify it at <http://localhost:4000>:

```bash
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.2.0/compose.yaml | docker compose -p expert-chat -f - start app
```

## Remove

Remove the containers and private network while preserving all data and secrets:

```bash
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.2.0/compose.yaml | docker compose -p expert-chat -f - down
```

The named volumes remain and the normal installation command can attach them again. To permanently erase the database and encryption material, add `--volumes`:

```bash
curl -fsSL https://raw.githubusercontent.com/experts-chat/appliance/v0.2.0/compose.yaml | docker compose -p expert-chat -f - down --volumes
```

The second command is destructive and cannot be undone without a complete backup containing both files shown above.

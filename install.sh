#!/usr/bin/env bash

set -Eeuo pipefail

readonly INSTALLER_VERSION="0.1.0"
readonly COMPOSE_REFERENCE="https://github.com/experts-chat/appliance.git#stable:compose.yaml"
readonly COMPOSE_DOWNLOAD_URL="${EXPERT_CHAT_COMPOSE_URL:-https://raw.githubusercontent.com/experts-chat/appliance/stable/compose.yaml}"
readonly PROJECT_NAME="${EXPERT_CHAT_PROJECT_NAME:-expert-chat}"
readonly APP_CONTAINER="${PROJECT_NAME}-app-1"
readonly DATABASE_VOLUME="${PROJECT_NAME}_postgres-data"
readonly SECRETS_VOLUME="${PROJECT_NAME}_installation-secrets"
readonly PINK="#D62564"
readonly WHITE="#FFFFFF"
readonly MUTED="#A1A1AA"
readonly MINIMUM_DOCKER_MEMORY_BYTES=2147483648
readonly MINIMUM_DOCKER_VERSION="24.0.0"
readonly MINIMUM_COMPOSE_VERSION="2.20.0"
readonly GUM_VERSION="0.17.0"

INSTALLER_TEMP=""
COMPOSE_FILE=""
GUM=""
PORT="${EXPERT_CHAT_PORT:-4000}"
BASE_URL=""
TEMPORARY_ACTIVE=0
EXISTING_INSTALLATION=0

cleanup() {
  local exit_code=$?
  trap - EXIT

  if [[ "$TEMPORARY_ACTIVE" == "1" ]] && command -v docker >/dev/null 2>&1; then
    printf '\n'
    info "Stopping the temporary appliance…"
    env EXPERT_CHAT_PORT="$PORT" docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" stop >/dev/null 2>&1 || true
    success "expert.chat has stopped. Your database and installation secrets are preserved."
  fi

  if [[ -n "$INSTALLER_TEMP" && -d "$INSTALLER_TEMP" ]]; then
    rm -rf -- "$INSTALLER_TEMP"
  fi

  exit "$exit_code"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

supports_colour() {
  [[ -t 1 && "${TERM:-}" != "dumb" ]]
}

pink_text() {
  if [[ -x "$GUM" ]]; then
    "$GUM" style --foreground "$PINK" "$*"
  elif supports_colour; then
    printf '\033[38;2;214;37;100m%s\033[0m' "$*"
  else
    printf '%s' "$*"
  fi
}

muted_text() {
  if [[ -x "$GUM" ]]; then
    "$GUM" style --foreground "$MUTED" "$*"
  else
    printf '%s' "$*"
  fi
}

section() {
  printf '\n%s\n\n' "$(pink_text "$*")"
}

success() {
  printf '  %s %s\n' "$(pink_text "✓")" "$*"
}

warning() {
  printf '  %s %s\n' "$(pink_text "!")" "$*"
}

info() {
  printf '  %s %s\n' "$(muted_text "·")" "$*"
}

fatal() {
  printf '\n%s\n' "$(pink_text "We could not continue")" >&2
  printf '%s\n' "$*" >&2
  exit 1
}

verify_sha256() {
  local expected="$1"
  local file="$2"

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s  %s\n' "$expected" "$file" | sha256sum --check --status
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s  %s\n' "$expected" "$file" | shasum -a 256 --check --status
  else
    return 1
  fi
}

bootstrap_gum() {
  local system machine asset checksum archive url

  command -v curl >/dev/null 2>&1 || return 1
  command -v tar >/dev/null 2>&1 || return 1

  system="$(uname -s 2>/dev/null || true)"
  machine="$(uname -m 2>/dev/null || true)"

  case "${system}_${machine}" in
    Linux_x86_64 | Linux_amd64)
      asset="gum_${GUM_VERSION}_Linux_x86_64.tar.gz"
      checksum="69ee169bd6387331928864e94d47ed01ef649fbfe875baed1bbf27b5377a6fdb"
      ;;
    Linux_aarch64 | Linux_arm64)
      asset="gum_${GUM_VERSION}_Linux_arm64.tar.gz"
      checksum="b0b9ed95cbf7c8b7073f17b9591811f5c001e33c7cfd066ca83ce8a07c576f9c"
      ;;
    Darwin_x86_64 | Darwin_amd64)
      asset="gum_${GUM_VERSION}_Darwin_x86_64.tar.gz"
      checksum="cd66576aeebe6cd19c771863c7e8d696e0e1d5387d1e7075666baa67c2052e53"
      ;;
    Darwin_arm64 | Darwin_aarch64)
      asset="gum_${GUM_VERSION}_Darwin_arm64.tar.gz"
      checksum="e2a4b8596efa05821d8c58d0c1afbcd7ad1699ba69c689cc3ff23a4a99c8b237"
      ;;
    *)
      return 1
      ;;
  esac

  archive="$INSTALLER_TEMP/$asset"
  url="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/${asset}"

  curl --fail --silent --show-error --location --retry 3 --output "$archive" "$url" >/dev/null 2>&1 || return 1
  verify_sha256 "$checksum" "$archive" || return 1
  tar -xzf "$archive" -C "$INSTALLER_TEMP" --strip-components=1 >/dev/null 2>&1 || return 1
  chmod 0700 "$INSTALLER_TEMP/gum"
  "$INSTALLER_TEMP/gum" --version >/dev/null 2>&1 || return 1
  GUM="$INSTALLER_TEMP/gum"
}

prepare_temporary_directory() {
  INSTALLER_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/expert-chat-install.XXXXXX")" || fatal "A private temporary directory could not be created."
  chmod 0700 "$INSTALLER_TEMP"
  COMPOSE_FILE="$INSTALLER_TEMP/compose.yaml"
}

welcome() {
  if [[ -x "$GUM" ]]; then
    "$GUM" style \
      --align center \
      --background "$PINK" \
      --border rounded \
      --border-foreground "$PINK" \
      --bold \
      --foreground "$WHITE" \
      --margin "1 0" \
      --padding "1 3" \
      --width 58 \
      "expert.chat" \
      "Your private, searchable data home"
  else
    printf '\n%s\n' "$(pink_text "══════════════════════════════════════════════════════")"
    printf '%s\n' "$(pink_text "                    expert.chat")"
    printf '%s\n' "$(pink_text "          Your private, searchable data home")"
    printf '%s\n\n' "$(pink_text "══════════════════════════════════════════════════════")"
  fi

  printf '\nexpert.chat keeps useful information from the services you already use\n'
  printf 'in a private appliance on this computer. This installer will check your\n'
  printf 'system, explain every change, and leave Docker to run the proven package.\n'
  info "Installer $INSTALLER_VERSION uses the reviewed stable appliance channel."
}

docker_install_help() {
  local system
  system="$(uname -s 2>/dev/null || true)"

  printf '\nInstall Docker from the official guide, then run this installer again:\n\n' >&2

  case "$system" in
    Darwin)
      printf '  https://docs.docker.com/desktop/setup/install/mac-install/\n' >&2
      ;;
    Linux)
      printf '  https://docs.docker.com/engine/install/\n' >&2
      ;;
    *)
      printf '  https://docs.docker.com/get-started/get-docker/\n' >&2
      ;;
  esac
}

confirm() {
  local prompt="$1"
  local affirmative="$2"
  local negative="$3"
  local answer status

  if [[ -x "$GUM" ]]; then
    "$GUM" confirm "$prompt" \
      --affirmative "$affirmative" \
      --default \
      --negative "$negative" \
      --prompt.foreground "$PINK" \
      --selected.background "$PINK" \
      --selected.foreground "$WHITE" \
      --unselected.foreground "$MUTED" \
      </dev/tty
    status=$?
    if ((status > 1)); then
      exit "$status"
    fi
    return "$status"
  fi

  printf '%s [Y/n] ' "$prompt" >/dev/tty
  IFS= read -r answer </dev/tty || return 1
  [[ -z "$answer" || "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" || "$answer" == "YES" ]]
}

valid_port() {
  local candidate="$1"
  [[ "$candidate" =~ ^[0-9]+$ ]] || return 1
  ((10#$candidate >= 1 && 10#$candidate <= 65535))
}

version_at_least() {
  local actual="${1#v}"
  local required="${2#v}"
  local actual_major actual_minor actual_patch required_major required_minor required_patch

  IFS=. read -r actual_major actual_minor actual_patch <<<"${actual%%[-+]*}"
  IFS=. read -r required_major required_minor required_patch <<<"${required%%[-+]*}"

  [[ "$actual_major" =~ ^[0-9]+$ && "$actual_minor" =~ ^[0-9]+$ && "${actual_patch:-0}" =~ ^[0-9]+$ ]] || return 1

  actual_patch="${actual_patch:-0}"
  required_patch="${required_patch:-0}"

  ((10#$actual_major > 10#$required_major)) ||
    ((10#$actual_major == 10#$required_major && 10#$actual_minor > 10#$required_minor)) ||
    ((10#$actual_major == 10#$required_major && 10#$actual_minor == 10#$required_minor && 10#$actual_patch >= 10#$required_patch))
}

port_is_open() {
  local candidate="$1"
  (exec 9<>"/dev/tcp/127.0.0.1/$candidate") >/dev/null 2>&1
}

prompt_for_port() {
  local suggestion="$1"
  local candidate

  while true; do
    if [[ -x "$GUM" ]]; then
      candidate="$("$GUM" input \
        --placeholder "$suggestion" \
        --prompt "Port: " \
        --prompt.foreground "$PINK" \
        </dev/tty)"
    else
      printf 'Choose another port [%s]: ' "$suggestion" >/dev/tty
      IFS= read -r candidate </dev/tty || return 1
    fi

    candidate="${candidate:-$suggestion}"

    if ! valid_port "$candidate"; then
      warning "Please enter a port between 1 and 65535."
    elif port_is_open "$candidate"; then
      warning "Port $candidate is already in use."
    else
      PORT="$candidate"
      return 0
    fi
  done
}

detect_existing_installation() {
  if docker container inspect "$APP_CONTAINER" >/dev/null 2>&1 ||
    docker volume inspect "$DATABASE_VOLUME" >/dev/null 2>&1 ||
    docker volume inspect "$SECRETS_VOLUME" >/dev/null 2>&1; then
    EXISTING_INSTALLATION=1
  fi
}

choose_port() {
  local existing_port=""
  local suggestion=4080

  if docker container inspect "$APP_CONTAINER" >/dev/null 2>&1; then
    existing_port="$(docker inspect --format '{{with (index .HostConfig.PortBindings "4000/tcp")}}{{(index . 0).HostPort}}{{end}}' "$APP_CONTAINER" 2>/dev/null || true)"
  fi

  if [[ -z "${EXPERT_CHAT_PORT:-}" && -n "$existing_port" ]]; then
    PORT="$existing_port"
  fi

  valid_port "$PORT" || fatal "EXPERT_CHAT_PORT must be a number between 1 and 65535."

  if port_is_open "$PORT" && [[ "$existing_port" != "$PORT" ]]; then
    warning "Port $PORT is already being used by another application."
    while port_is_open "$suggestion"; do
      suggestion=$((suggestion + 1))
    done
    prompt_for_port "$suggestion" || fatal "A free local port is required."
    success "Port $PORT is available."
  elif [[ "$existing_port" == "$PORT" ]]; then
    success "The existing appliance uses port $PORT."
  else
    success "Port $PORT is available."
  fi

  BASE_URL="http://127.0.0.1:$PORT"
}

doctor() {
  local docker_error docker_version compose_version machine memory_bytes memory_gib compose_output

  section "Let’s make sure this computer is ready"

  if ((EUID == 0)); then
    fatal "Run this installer from your normal account, without sudo. Docker should grant that account access through Docker Desktop or the docker group."
  fi

  if ! command -v docker >/dev/null 2>&1; then
    docker_install_help
    fatal "Docker is not installed."
  fi

  if ! docker_error="$(docker info 2>&1)"; then
    if [[ "$docker_error" == *"permission denied"* || "$docker_error" == *"docker.sock"* ]]; then
      fatal $'Docker is running, but this account cannot use it. If you were recently added to the docker group, run `newgrp docker` now; log out and back in once to make the permission permanent.'
    fi

    docker_install_help
    fatal $'The Docker command is installed, but its engine is not available. Start Docker Desktop or the Docker service, then try again.\n\nDocker said:\n'"$docker_error"
  fi

  docker_version="$(docker version --format '{{.Server.Version}}' 2>/dev/null || printf 'unknown')"
  if ! version_at_least "$docker_version" "$MINIMUM_DOCKER_VERSION"; then
    docker_install_help
    fatal "Docker $docker_version is installed, but expert.chat needs Docker $MINIMUM_DOCKER_VERSION or newer. Update Docker, then try again."
  fi
  success "Docker $docker_version is running."

  if ! compose_version="$(docker compose version --short 2>/dev/null)"; then
    docker_install_help
    fatal "Docker Compose is not available through the ‘docker compose’ command."
  fi
  if ! version_at_least "$compose_version" "$MINIMUM_COMPOSE_VERSION"; then
    docker_install_help
    fatal "Docker Compose $compose_version is installed, but expert.chat needs Docker Compose $MINIMUM_COMPOSE_VERSION or newer. Update Docker, then try again."
  fi
  success "Docker Compose $compose_version is available."

  machine="$(uname -m 2>/dev/null || true)"
  case "$machine" in
    x86_64 | amd64)
      success "This amd64 computer is supported by the current appliance release."
      ;;
    arm64 | aarch64)
      fatal "The current pre-v1 appliance is amd64-only. Native Apple Silicon support must pass its launch gate before this installer will enable it; emulation is not accepted as a substitute."
      ;;
    *)
      fatal "This computer reports architecture ‘$machine’, which the current appliance release does not support."
      ;;
  esac

  memory_bytes="$(docker info --format '{{.MemTotal}}' 2>/dev/null || true)"
  if [[ "$memory_bytes" =~ ^[0-9]+$ ]]; then
    memory_gib="$(awk -v bytes="$memory_bytes" 'BEGIN {printf "%.1f", bytes / 1073741824}')"
    if ((memory_bytes < MINIMUM_DOCKER_MEMORY_BYTES)); then
      warning "Docker has $memory_gib GiB available; expert.chat recommends at least 2 GiB."
      confirm "Continue with less than the recommended memory?" "Continue" "Stop" || fatal "Increase Docker’s memory allocation, then run the installer again."
    else
      success "Docker has $memory_gib GiB available."
    fi
  else
    warning "Docker’s available memory could not be measured; allow at least 2 GiB."
  fi

  if [[ -x "$GUM" ]]; then
    if ! "$GUM" spin \
      --show-error \
      --spinner pulse \
      --spinner.foreground "$PINK" \
      --title "Checking the expert.chat package…" \
      --title.foreground "$MUTED" \
      -- curl --fail --silent --show-error --location --retry 3 --output "$COMPOSE_FILE" "$COMPOSE_DOWNLOAD_URL"; then
      fatal "Docker Compose could not read the public expert.chat package. Check your network connection and Docker installation, then try again."
    fi
  elif ! curl --fail --silent --show-error --location --retry 3 --output "$COMPOSE_FILE" "$COMPOSE_DOWNLOAD_URL"; then
    fatal "The public expert.chat package could not be downloaded. Check your network connection, then try again."
  fi

  if ! compose_output="$(docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" config --services 2>&1)"; then
    fatal $'Docker Compose could not read the public expert.chat package.\n\nDocker said:\n'"$compose_output"
  fi

  if ! grep -qx "app" <<<"$compose_output" || ! grep -qx "db" <<<"$compose_output"; then
    fatal "The public package did not contain the expected application and database services. Nothing has been started."
  fi
  success "The reviewed expert.chat package is available."

  detect_existing_installation
  choose_port
}

explain_installation() {
  section "What we are about to do"

  if [[ "$EXISTING_INSTALLATION" == "1" ]]; then
    printf 'An existing expert.chat installation was found. We will keep its database\n'
    printf 'and encryption keys, then bring its two containers to the currently accepted\n'
    printf 'release. Nothing in its persistent volumes will be replaced.\n'
  else
    printf 'Docker will start the expert.chat application and PostgreSQL. It will create\n'
    printf 'two persistent volumes: one for your database, and one for the encryption\n'
    printf 'keys that protect sessions and saved Credentials. Only %s is exposed.\n' "$BASE_URL"
  fi

  printf '\nRoutine Docker logs will stay out of the way. If startup fails, the useful\n'
  printf 'diagnostics will be shown automatically.\n'
}

choose_run_mode() {
  if confirm "Keep expert.chat running in the background?" "Keep it running" "Run temporarily"; then
    printf 'background'
  else
    printf 'temporary'
  fi
}

start_appliance() {
  local mode="$1"
  local -a command

  command=(env EXPERT_CHAT_PORT="$PORT" docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" up -d --remove-orphans)

  if [[ "$mode" == "temporary" ]]; then
    TEMPORARY_ACTIVE=1
  fi

  if [[ -x "$GUM" ]]; then
    "$GUM" spin \
      --show-error \
      --spinner pulse \
      --spinner.foreground "$PINK" \
      --title "Downloading and starting expert.chat…" \
      --title.foreground "$MUTED" \
      -- "${command[@]}" || fatal "Docker could not start expert.chat. The diagnostic output above contains the underlying error."
  else
    info "Downloading and starting expert.chat. This can take a few minutes…"
    "${command[@]}" || fatal "Docker could not start expert.chat."
  fi
}

wait_for_readiness() {
  local url="$1"
  local deadline=$((SECONDS + 300))

  while ((SECONDS < deadline)); do
    if curl --fail --silent --show-error --max-time 2 "$url/api/v1/ready" 2>/dev/null | grep -q '"status":"ready"'; then
      return 0
    fi
    sleep 2
  done

  return 1
}

show_failure_logs() {
  printf '\nRecent container logs:\n\n' >&2
  env EXPERT_CHAT_PORT="$PORT" docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" logs --no-color --tail 120 app db >&2 || true
}

wait_until_ready() {
  if [[ -x "$GUM" ]]; then
    # shellcheck disable=SC2016
    if ! "$GUM" spin \
      --show-error \
      --spinner pulse \
      --spinner.foreground "$PINK" \
      --title "Waiting for the database and application…" \
      --title.foreground "$MUTED" \
      -- bash -c '
        url="$1"
        deadline=$((SECONDS + 300))
        while ((SECONDS < deadline)); do
          if curl --fail --silent --show-error --max-time 2 "$url/api/v1/ready" 2>/dev/null | grep -q '\''"status":"ready"'\''; then
            exit 0
          fi
          sleep 2
        done
        exit 1
      ' installer-readiness "$BASE_URL"; then
      show_failure_logs
      fatal "expert.chat did not become ready within five minutes."
    fi
  elif ! wait_for_readiness "$BASE_URL"; then
    show_failure_logs
    fatal "expert.chat did not become ready within five minutes."
  fi
}

setup_is_required() {
  local status
  status="$(curl --fail --silent --show-error --max-time 5 "$BASE_URL/api/v1/status" 2>/dev/null || true)"
  grep -Eq '"setup_required"[[:space:]]*:[[:space:]]*true' <<<"$status"
}

read_setup_code() {
  local logs
  logs="$(env EXPERT_CHAT_PORT="$PORT" docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" logs --no-color app 2>/dev/null || true)"
  sed -n 's/.*Setup code: \([A-Z0-9-][A-Z0-9-]*\).*/\1/p' <<<"$logs" | tail -n 1
}

show_ready() {
  local setup_code=""

  if setup_is_required; then
    setup_code="$(read_setup_code)"
    [[ -n "$setup_code" ]] || fatal "expert.chat is ready, but the installer could not read its one-time setup code. Run ‘docker compose -f $COMPOSE_REFERENCE logs app’ to see the startup message."

    if [[ -x "$GUM" ]]; then
      printf '\n'
      "$GUM" style \
        --align center \
        --background "$PINK" \
        --border rounded \
        --border-foreground "$PINK" \
        --bold \
        --foreground "$WHITE" \
        --padding "1 3" \
        --width 58 \
        "Your appliance is ready" \
        "Setup code" \
        "$setup_code"
    else
      section "Your appliance is ready"
      printf 'Setup code: %s\n' "$setup_code"
    fi

    printf '\nOpen %s and enter this one-time code.\n' "$BASE_URL"
  else
    if [[ -x "$GUM" ]]; then
      printf '\n'
      "$GUM" style \
        --align center \
        --border rounded \
        --border-foreground "$PINK" \
        --bold \
        --foreground "$PINK" \
        --padding "1 3" \
        --width 58 \
        "Welcome back" \
        "Your expert.chat appliance is ready"
    else
      section "Welcome back — your expert.chat appliance is ready"
    fi

    printf '\nOpen %s to continue.\n' "$BASE_URL"
  fi
}

browser_command() {
  local system
  system="$(uname -s 2>/dev/null || true)"

  [[ -z "${SSH_CONNECTION:-}" && -z "${SSH_TTY:-}" ]] || return 1

  case "$system" in
    Linux)
      [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]] || return 1
      command -v xdg-open >/dev/null 2>&1 || return 1
      printf 'xdg-open'
      ;;
    Darwin)
      command -v open >/dev/null 2>&1 || return 1
      printf 'open'
      ;;
    *)
      return 1
      ;;
  esac
}

offer_browser() {
  local opener

  if ! opener="$(browser_command)"; then
    info "No graphical browser was detected, so the installer will leave the URL for you to open."
    return
  fi

  printf '\n%s\n' "$(pink_text "Press any key to open expert.chat in your default browser, or Ctrl+C to leave it closed.")"
  IFS= read -r -s -n 1 </dev/tty || return
  printf '\n'
  ("$opener" "$BASE_URL" >/dev/null 2>&1 &)
  success "The browser was asked to open $BASE_URL."
}

wait_for_temporary_exit() {
  section "expert.chat is running temporarily"
  printf 'Leave this terminal open while you use the appliance. Press Ctrl+C when\n'
  printf 'you are finished; the containers will stop and your saved data will remain.\n'

  while true; do
    sleep 86400
  done
}

main() {
  local run_mode action

  if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
    fatal "This friendly installer needs an interactive terminal. Open a terminal and run the command there."
  fi

  prepare_temporary_directory
  bootstrap_gum || true
  welcome

  if [[ ! -x "$GUM" ]]; then
    warning "The temporary interface helper could not be verified, so the installer is continuing with plain text."
  fi

  doctor
  explain_installation
  run_mode="$(choose_run_mode)"

  if [[ "$EXISTING_INSTALLATION" == "1" ]]; then
    action="Start or update expert.chat now?"
  else
    action="Start expert.chat now?"
  fi

  if ! confirm "$action" "Start expert.chat" "Not yet"; then
    printf '\nNothing was changed. Run the installer whenever you are ready.\n'
    return
  fi

  start_appliance "$run_mode"
  wait_until_ready
  success "PostgreSQL is ready."
  success "expert.chat is ready."
  show_ready
  offer_browser

  if [[ "$run_mode" == "temporary" ]]; then
    wait_for_temporary_exit
  fi
}

main "$@"

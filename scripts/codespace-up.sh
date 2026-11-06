#!/bin/sh
# Start the Moodle Lab in a GitHub Codespace and point Moodle at the current
# forwarded HTTPS URL. This avoids the "Must use https address in wwwroot
# when ssl proxy enabled" error and the 127.0.0.1 redirect loop.
#
# Usage:
#   sh scripts/codespace-up.sh
#
# Local users should keep using:
#   docker compose -f compose.yaml -f compose.vuln.yaml up -d
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT" || exit 1

if [ ! -f .env ]; then
    cp .env.example .env
    echo "Created .env from .env.example."
fi

# Load current settings without letting an empty MOODLE_WWWROOT override the
# auto-detection below.
set -a
. ./.env
set +a

PORT=${MOODLE_PORT:-8080}
NAME=${CODESPACE_NAME:-}
DOMAIN=${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}

# SSH shells used by some editors do not inherit the Codespaces remoteEnv.
# The shared file is readable by the codespace user and contains only the
# values GitHub injects into the container; read just the two keys we need.
SHARED_ENV=/workspaces/.codespaces/shared/.env
if { [ -z "$NAME" ] || [ -z "$DOMAIN" ]; } && [ -r "$SHARED_ENV" ]; then
    [ -n "$NAME" ] || NAME=$(sed -n 's/^CODESPACE_NAME=//p' "$SHARED_ENV" | head -n 1)
    [ -n "$DOMAIN" ] || DOMAIN=$(sed -n 's/^GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=//p' "$SHARED_ENV" | head -n 1)
fi

if [ -z "$NAME" ] || [ -z "$DOMAIN" ]; then
    echo "FAIL: not running in a GitHub Codespace (CODESPACE_NAME or forwarding domain is missing)." >&2
    echo "For local use: docker compose -f compose.yaml -f compose.vuln.yaml up -d" >&2
    exit 1
fi

URL="https://${NAME}-${PORT}.${DOMAIN}"

# Keep the URL in .env so wait-moodle.sh, env-check.sh, the browser, and future
# restarts all use the same value. Do not ask beginners to edit hosts files.
if grep -q '^MOODLE_WWWROOT=' .env; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/p2s-env.XXXXXX")
    sed "s|^MOODLE_WWWROOT=.*|MOODLE_WWWROOT=${URL}|" .env > "$tmp"
    mv "$tmp" .env
else
    printf '\nMOODLE_WWWROOT=%s\n' "$URL" >> .env
fi

echo "Codespace URL: $URL"
# We sourced .env above, so an empty MOODLE_WWWROOT may already be exported.
# Export the new values explicitly; shell environment takes precedence over
# .env for Compose interpolation.
export MOODLE_WWWROOT="$URL"
export MOODLE_PORT="$PORT"
export CODESPACE_NAME="$NAME"
export GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN="$DOMAIN"
sh scripts/init-lab-config.sh
echo "Rebuilding the Moodle image and recreating the container..."
# --build is intentional: an older prebuilt image may contain an entrypoint
# that left sslproxy=true with a localhost wwwroot.
docker compose -f compose.yaml -f compose.vuln.yaml up -d --build --force-recreate moodle

if ! sh scripts/wait-moodle.sh; then
    echo
    echo "Moodle did not become ready. Recent logs:" >&2
    docker compose -f compose.yaml -f compose.vuln.yaml logs --tail=100 moodle >&2 || true
    exit 1
fi

echo
echo "Open in the browser: $URL"
echo "The port must be reachable from your browser (Private is fine; sign in if prompted)."

#!/bin/sh
# Switch the lab between the vulnerable PHP 8.3.35 image and the patched
# PHP 8.3.36 image, then verify what is actually running.
#
# Usage:
#   sh scripts/switch-php.sh 8.3.35
#   sh scripts/switch-php.sh 8.3.36
#
# The Moodle database and volumes are preserved. Previous PoC proof files in
# loot/ are removed by default so a stale success cannot be mistaken for a new
# result; pass --keep-evidence to keep them.
set -u

# ANSI colors for interactive terminals; redirected logs stay plain.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_RED=$(printf '\033[31m')
    C_GREEN=$(printf '\033[32m')
    C_YELLOW=$(printf '\033[33m')
    C_RESET=$(printf '\033[0m')
else
    C_RED=
    C_GREEN=
    C_YELLOW=
    C_RESET=
fi

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT" || exit 1

VERSION=${1:-}
KEEP=0
case "${2:-}" in
    --keep-evidence) KEEP=1 ;;
    '') ;;
    *) echo "unknown option: $2" >&2; exit 2 ;;
esac

case "$VERSION" in
    8.3.35) FILES="-f compose.yaml -f compose.vuln.yaml"; IMAGE="moodle-php-lab-moodle:8.3.35" ;;
    8.3.36) FILES="-f compose.yaml -f compose.vuln.yaml -f compose.patched.yaml"; IMAGE="moodle-php-lab-moodle:8.3.36" ;;
    *) echo "usage: sh scripts/switch-php.sh 8.3.35|8.3.36 [--keep-evidence]" >&2; exit 2 ;;
esac

if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi
PORT=${MOODLE_PORT:-8080}
WWWROOT=${MOODLE_WWWROOT:-}
WWWROOT=${WWWROOT%/}
sh scripts/init-lab-config.sh

COMPOSE="docker compose $FILES"

if ! docker info >/dev/null 2>&1; then
    printf '%sFAIL:%s Docker daemon is not reachable.\n' "$C_RED" "$C_RESET" >&2
    exit 1
fi

echo "Switching Moodle to PHP ${VERSION} (${IMAGE})..."
# shellcheck disable=SC2086
if ! $COMPOSE up -d --force-recreate moodle; then
    printf '%sFAIL:%s docker compose could not start the %s container.\n' "$C_RED" "$C_RESET" "$VERSION" >&2
    exit 1
fi

CONTAINER=$($COMPOSE ps -q moodle 2>/dev/null || true)
if [ -z "$CONTAINER" ]; then
    printf '%sFAIL:%s Moodle container was not created.\n' "$C_RED" "$C_RESET" >&2
    exit 1
fi

URL="http://127.0.0.1:${PORT}/login/index.php"
echo "Waiting for $URL ..."
i=0
moodle_ready() {
    code=$(curl -s -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null || true)
    [ "$code" = "200" ] && return 0
    [ -n "$WWWROOT" ] || return 1
    location=$(curl -s -o /dev/null -w '%{redirect_url}' "$URL" 2>/dev/null || true)
    case "$location" in
        "$WWWROOT"*) return 0 ;;
    esac
    return 1
}
until moodle_ready; do
    i=$((i + 1))
    if [ "$i" -ge 96 ]; then
        printf '%sFAIL:%s Moodle did not become ready within 8 minutes.\n' "$C_RED" "$C_RESET" >&2
        echo "Check: $COMPOSE logs --tail=80 moodle" >&2
        exit 1
    fi
    printf '  %sstill starting... (%ss)%s\n' "$C_YELLOW" "$((i * 5))" "$C_RESET"
    sleep 5
done

ACTUAL=$($COMPOSE exec -T moodle php -r 'echo PHP_VERSION;' 2>/dev/null || true)
RUNNING_IMAGE=$(docker inspect --format '{{.Config.Image}}' "$CONTAINER" 2>/dev/null || true)

FAIL=0
if [ "$ACTUAL" = "$VERSION" ]; then
    printf '  %s[PASS]%s container PHP: %s\n' "$C_GREEN" "$C_RESET" "$ACTUAL"
else
    printf '  %s[FAIL]%s container PHP: %s (expected %s)\n' "$C_RED" "$C_RESET" "${ACTUAL:-unknown}" "$VERSION" >&2
    FAIL=1
fi
if [ "$RUNNING_IMAGE" = "$IMAGE" ]; then
    printf '  %s[PASS]%s running image: %s\n' "$C_GREEN" "$C_RESET" "$RUNNING_IMAGE"
else
    printf '  %s[FAIL]%s running image: %s (expected %s)\n' "$C_RED" "$C_RESET" "${RUNNING_IMAGE:-unknown}" "$IMAGE" >&2
    FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
    printf '%sFAIL:%s the requested PHP version is not the one actually running.\n' "$C_RED" "$C_RESET" >&2
    echo "Check: $COMPOSE ps" >&2
    echo "Check: $COMPOSE logs --tail=80 moodle" >&2
    exit 1
fi

if [ "$KEEP" -eq 0 ]; then
    rm -f loot/p1 loot/c loot/grade-progress.txt
    printf '  %s[PASS]%s cleared previous proof files (loot/p1, loot/c, loot/grade-progress.txt)\n' "$C_GREEN" "$C_RESET"
fi

echo
printf '%sPHP_SWITCH=ok%s version=%s image=%s container=%s\n' "$C_GREEN" "$C_RESET" "$VERSION" "$IMAGE" "$CONTAINER"
echo "  export CONTAINER=${CONTAINER}"

#!/bin/sh
# Wait until the local Moodle lab answers 200, up to 8 minutes.
# Usage: sh scripts/wait-moodle.sh
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

# Work from the repository root even when the script is called from elsewhere.
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT" || exit 1

if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi
PORT=${MOODLE_PORT:-8080}
WWWROOT=${MOODLE_WWWROOT:-}
WWWROOT=${WWWROOT%/}

COMPOSE="docker compose -f compose.yaml -f compose.vuln.yaml"
URL="http://127.0.0.1:${PORT}/index.php"
i=0

printf 'Waiting for %s (up to 8 minutes)...\n' "$URL"

http_ready() {
    code=$(curl -s -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null || true)
    [ "$code" = "200" ] && return 0
    [ -n "$WWWROOT" ] || return 1
    location=$(curl -s -o /dev/null -w '%{redirect_url}' "$URL" 2>/dev/null || true)
    case "$location" in
        "$WWWROOT"*) return 0 ;;
    esac
    return 1
}

until http_ready; do
    i=$((i + 1))
    if [ "$i" -ge 96 ]; then
        printf '%sStill not ready after 8 minutes.%s\n' "$C_RED" "$C_RESET" >&2
        printf 'Check: %s ps\n' "$COMPOSE" >&2
        printf 'Logs:  %s logs --tail=50 moodle\n' "$COMPOSE" >&2
        exit 1
    fi
    printf '  %sstill installing... (%ss)%s\n' "$C_YELLOW" "$((i * 5))" "$C_RESET"
    sleep 5
done

BASELINE=$($COMPOSE exec -T moodle php -r '
define("CLI_SCRIPT", true);
require("/var/www/html/config.php");
echo get_config("core", "lab_ui_initialized") ? "1" : "0";
echo $DB->record_exists("user", ["username" => "p2s_student", "deleted" => 0]) ? "1" : "0";
' 2>/dev/null || true)

if [ "$BASELINE" = "11" ]; then
    printf '%sMoodle is up:%s %s (baseline ready)\n' "$C_GREEN" "$C_RESET" "$URL"
else
    printf '%sMoodle answered, but the baseline is incomplete (marker/user=%s).%s\n' "$C_RED" "${BASELINE:-unknown}" "$C_RESET" >&2
    printf 'Check: %s logs --tail=80 moodle\n' "$COMPOSE" >&2
    exit 1
fi

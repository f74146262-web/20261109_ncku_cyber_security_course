#!/bin/sh
# Student-side sanity check before running the exploit.
#
# Usage:
#   sh scripts/env-check.sh          # vulnerable PHP 8.3.35
#   sh scripts/env-check.sh 8.3.36   # patched image
#
# This script verifies the container, the CLI view of php.ini, and the static
# Apache configuration. It does NOT prove the Apache mod_php request-startup
# values by itself: the exploit's stage 1 heap leak is the runtime proof that
# /index.php actually starts with 8M / 1000 / display_errors=On.
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

EXPECTED=${1:-8.3.35}
case "$EXPECTED" in
    8.3.35) FILES="-f compose.yaml -f compose.vuln.yaml" ;;
    8.3.36) FILES="-f compose.yaml -f compose.vuln.yaml -f compose.patched.yaml" ;;
    *) echo "usage: sh scripts/env-check.sh [8.3.35|8.3.36]" >&2; exit 2 ;;
esac

if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi
PORT=${MOODLE_PORT:-8080}
WWWROOT=${MOODLE_WWWROOT:-}
WWWROOT=${WWWROOT%/}

ok() { printf '  %s[PASS]%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
bad() { printf '  %s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$1"; FAIL=1; }
FAIL=0

if [ ! -f compose.yaml ] || [ ! -f compose.vuln.yaml ]; then
    bad 'run this from the project root (compose.yaml not found)'
    exit 1
fi
ok 'project root'

if [ ! -f .env ]; then
    bad '.env is missing; run: cp .env.example .env'
else
    ok '.env exists'
fi

COMPOSE="docker compose $FILES"
CONTAINER=$($COMPOSE ps -q moodle 2>/dev/null || true)
if [ -z "$CONTAINER" ]; then
    bad "Moodle container is not running"
    printf '  Fix: %s up -d\n' "$COMPOSE"
    printf '  Then: %s logs --tail=50 moodle\n' "$COMPOSE"
    exit 1
fi
ok "Moodle container: $CONTAINER"

if [ ! -w loot ]; then
    bad 'loot/ is not writable by this user'
else
    ok 'loot/ is writable'
fi

VERSION=$($COMPOSE exec -T moodle php -r 'echo PHP_VERSION;' 2>/dev/null || true)
if [ "$VERSION" = "$EXPECTED" ]; then
    ok "container PHP CLI version: $VERSION"
else
    bad "container PHP CLI version is '${VERSION:-unknown}', expected $EXPECTED"
fi

RUNNING_IMAGE=$(docker inspect --format '{{.Config.Image}}' "$CONTAINER" 2>/dev/null || true)
EXPECTED_IMAGE="moodle-php-lab-moodle:${EXPECTED}"
if [ "$RUNNING_IMAGE" = "$EXPECTED_IMAGE" ]; then
    ok "running image: $RUNNING_IMAGE"
else
    bad "running image is '${RUNNING_IMAGE:-unknown}', expected $EXPECTED_IMAGE"
fi

# These values come from php.ini as seen by the CLI. Apache mod_php reads the
# same files plus apache.conf overrides; the separate checks below cover the
# static Apache side, and the exploit covers the live request startup.
GLOBALS=$($COMPOSE exec -T moodle php -r 'echo ini_get("memory_limit"), " ", ini_get("max_input_vars"), " ", ini_get("display_errors");' 2>/dev/null || true)
if [ "$GLOBALS" = "8M 1000 1" ]; then
    ok 'CLI php.ini globals: 8M / 1000 / display_errors=On'
else
    bad "CLI php.ini globals are '${GLOBALS:-unknown}', expected '8M 1000 1'"
    printf '  Fix: edit labs/vuln/php.ini: memory_limit=8M, max_input_vars=1000, display_errors=On\n'
fi

if $COMPOSE exec -T moodle sh -c 'apache2ctl -M 2>/dev/null | grep -q php_module' >/dev/null 2>&1; then
    ok 'Apache mod_php module is loaded'
else
    bad 'Apache mod_php module is not loaded'
fi

if $COMPOSE exec -T moodle test -f /etc/apache2/conf-enabled/zz-vuln.conf >/dev/null 2>&1; then
    ok 'Apache lab config is mounted'
else
    bad 'Apache lab config /etc/apache2/conf-enabled/zz-vuln.conf is missing'
fi

WORKERS=$($COMPOSE exec -T moodle sh -c 'grep -E "MaxRequestWorkers" /etc/apache2/conf-enabled/zz-vuln.conf 2>/dev/null' || true)
if printf '%s\n' "$WORKERS" | grep -Eq '^[[:space:]]*MaxRequestWorkers[[:space:]]+1([[:space:]]|$)'; then
    ok 'static Apache config: single prefork worker'
else
    bad "MaxRequestWorkers is not 1: ${WORKERS:-unknown}"
    printf '  Fix: edit labs/vuln/apache.conf and set MaxRequestWorkers 1\n'
fi

if $COMPOSE exec -T moodle sh -c 'grep -q "LocationMatch" /etc/apache2/conf-enabled/zz-vuln.conf' >/dev/null 2>&1; then
    ok 'static Apache config: non-index PHP pages get the 256M override'
else
    bad 'Apache lab config does not contain the non-index override'
    printf '  Fix: edit labs/vuln/apache.conf and add the LocationMatch 256M/5000/Off block\n'
fi

# Check the four php_value lines in the mounted Apache config. This is a
# static file check; it does not prove the live Apache parser accepted them.
APACHE_VALUES=$($COMPOSE exec -T moodle sh -c 'grep -E "^[[:space:]]*php_value[[:space:]]+" /etc/apache2/conf-enabled/zz-vuln.conf 2>/dev/null' || true)
for spec in "memory_limit 256M" "max_input_vars 5000" "display_errors Off" "display_startup_errors Off"; do
    key=${spec%% *}
    value=${spec#* }
    if printf '%s\n' "$APACHE_VALUES" | grep -Eq "^[[:space:]]*php_value[[:space:]]+${key}[[:space:]]+${value}([[:space:]]|$)"; then
        ok "Apache php_value ${key} ${value}"
    else
        bad "Apache php_value ${key} is not ${value}"
        printf '  Fix: edit labs/vuln/apache.conf and set php_value %s %s\n' "$key" "$value"
    fi
done

CONFIG_MEM=$($COMPOSE exec -T moodle sh -c 'grep -c "ini_set(\"memory_limit\", \"256M\")" /var/www/config/config.php 2>/dev/null' || true)
if [ "$CONFIG_MEM" != "0" ] && [ -n "$CONFIG_MEM" ]; then
    ok 'config.php raises the runtime memory limit after startup'
else
    bad 'config.php is missing the 256M ini_set line'
fi

for path in index.php login/index.php; do
    URL="http://127.0.0.1:${PORT}/$path"
    CODE=$(curl -s -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null || true)
    if [ "$CODE" = "200" ]; then
        ok "/$path -> 200"
        continue
    fi
    LOCATION=$(curl -s -o /dev/null -w '%{redirect_url}' "$URL" 2>/dev/null || true)
    if [ -n "$WWWROOT" ]; then
        case "$LOCATION" in
            "$WWWROOT"*)
                ok "/$path -> ${CODE} to configured MOODLE_WWWROOT"
                continue
                ;;
        esac
    fi
    bad "/$path -> ${CODE:-no response}; if you just ran 'up -d', wait up to 8 minutes, then re-run this script; otherwise check: $COMPOSE logs --tail=50 moodle"
done

printf '  [INFO] Apache mod_php request values are not fully observable from the CLI.\n'
printf '         The exploit stage 1 heap leak is the runtime confirmation.\n'

if [ "$FAIL" -ne 0 ]; then
    printf '\n%sResult: FAIL.%s Fix the items above before running the exploit.\n' "$C_RED" "$C_RESET"
    printf '  Required edits: labs/vuln/php.ini and labs/vuln/apache.conf\n'
    printf '  Then recreate Moodle: %s up -d --force-recreate moodle\n' "$COMPOSE"
    exit 1
fi
printf '\n%sResult: PASS for container %s (PHP %s).%s\n' "$C_GREEN" "$CONTAINER" "$EXPECTED" "$C_RESET"
printf '  export CONTAINER=%s\n' "$CONTAINER"

#!/bin/sh
# Pre-class environment check for the student Moodle lab.
#
# It does NOT start containers and does NOT run the exploit.
# Usage: sh scripts/prelab-check.sh
#
# Exit code:
#   0  required checks passed (warnings may still need attention)
#   1  a required check failed; the lab is not ready
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

# Create ignored local configs from tracked templates before checking them.
if [ -x scripts/init-lab-config.sh ]; then
    sh scripts/init-lab-config.sh
fi

FAIL=0
WARN=0
ok()   { printf '  %s[PASS]%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn() { printf '  %s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; WARN=$((WARN + 1)); }
bad()  { printf '  %s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$1"; FAIL=1; }
hint() {
    printf '\nNext steps:\n'
    printf '  - fix every %s[FAIL]%s item and re-run this script\n' "$C_RED" "$C_RESET"
    printf '  - review %s[WARN]%s items before class\n' "$C_YELLOW" "$C_RESET"
    printf '  - full instructions: README.md\n'
}

OS=$(uname -s)
ARCH=$(uname -m)

if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi
PORT=${MOODLE_PORT:-8080}

echo "Host: $OS / $ARCH"
echo "Moodle port: $PORT"

case "$OS" in
    MINGW*|MSYS*|CYGWIN*)
        warn 'Git Bash detected; the course is tested in WSL2. Use WSL2 if Docker commands fail.'
        ;;
esac

if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    if [ "$OS" = "Darwin" ]; then
        warn 'Apple Silicon requires Docker amd64 emulation; expect slower builds and runs.'
    else
        bad 'ARM host (Linux or Windows on ARM) is not supported; use an x86-64 machine'
    fi
fi

if ! docker info >/dev/null 2>&1; then
    bad 'Docker daemon is not reachable; start Docker Desktop or OrbStack'
    hint
    exit 1
fi
ok 'Docker daemon is reachable'

if ! docker compose version >/dev/null 2>&1; then
    bad 'docker compose v2 is not available'
    hint
    exit 1
fi
ok "docker compose is available ($(docker compose version --short 2>/dev/null))"

if docker compose -f compose.yaml -f compose.vuln.yaml config --quiet >/dev/null 2>&1; then
    ok 'compose.yaml + compose.vuln.yaml is valid'
else
    bad 'Compose configuration is invalid; run this from the project root'
fi

if docker compose -f compose.yaml -f compose.vuln.yaml -f compose.patched.yaml config --quiet >/dev/null 2>&1; then
    ok 'compose.patched.yaml overlay is valid'
else
    bad 'compose.patched.yaml overlay is invalid'
fi

if docker compose -f php2shell/docker/docker-compose.yml config --quiet >/dev/null 2>&1; then
    ok 'upstream minimal target Compose file is valid'
else
    bad 'upstream minimal target Compose file is invalid'
fi

if python3 scripts/check_ports.py compose.yaml compose.vuln.yaml compose.patched.yaml >/dev/null 2>&1; then
    ok 'published ports are bound to 127.0.0.1'
else
    bad 'a published port is not bound to 127.0.0.1'
fi

case "$PORT" in
    ''|*[!0-9]*) bad "MOODLE_PORT is not a number: ${PORT}" ;;
    *)
        if [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
            ok "MOODLE_PORT=${PORT}"
        else
            bad "MOODLE_PORT is out of range: ${PORT}"
        fi
        ;;
esac

if command -v python3 >/dev/null 2>&1; then
    PYV=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)
    case "$PYV" in
        3.9|3.1[0-9]|3.[2-9][0-9]) ok "python3 ${PYV} (the exploit needs >= 3.9)" ;;
        *) bad "python3 ${PYV} is too old; the exploit needs >= 3.9" ;;
    esac
else
    bad 'python3 not found'
fi

if command -v curl >/dev/null 2>&1; then ok 'curl is available'; else bad 'curl not found'; fi

AVAIL_KB=$(df -Pk . | awk 'NR==2 {print $4}')
AVAIL_GB=$(awk -v k="$AVAIL_KB" 'BEGIN { printf "%d", k / 1048576 }')
printf '  Available disk: %s GiB\n' "$AVAIL_GB"
if [ "$AVAIL_GB" -ge 10 ]; then
    ok 'enough disk space (>= 10 GiB)'
elif [ "$AVAIL_GB" -ge 6 ]; then
    warn 'disk space is tight; builds may fail'
elif docker image inspect moodle-php-lab-moodle:8.3.35 >/dev/null 2>&1 && \
     docker image inspect moodle-php-lab-moodle:8.3.36 >/dev/null 2>&1; then
    warn 'disk space is tight, but both Moodle images are already built'
else
    bad 'not enough disk space (< 6 GiB) and Moodle images are not built'
fi

if command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
        if docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' 2>/dev/null | grep ":${PORT}->80/tcp" | grep -q "moodle-php-lab-moodle"; then
            ok "port ${PORT} is already served by the lab container"
        else
            warn "port ${PORT} is used by another process; stop it or set MOODLE_PORT in .env"
        fi
    else
        ok "port ${PORT} is available"
    fi
fi

for f in compose.yaml compose.vuln.yaml compose.patched.yaml Dockerfile entrypoint.sh php-lab.ini .dockerignore \
         moodle-ui.php \
         labs/vuln/php.ini.template labs/vuln/apache.conf.template \
         labs/vuln/php.ini labs/vuln/apache.conf \
         labs/examples/homepage.php labs/examples/reset-homepage.php \
         labs/examples/grade.php labs/examples/reset-grade.php \
         labs/examples/rickroll.php labs/examples/reset-rickroll.php \
         php2shell/exploit.py php2shell/docker/offsets.py php2shell/VENDORED.md \
         php2shell/docker/docker-compose.yml php2shell/docker/php.ini \
         php2shell/docker/apache.conf php2shell/docker/www/index.php; do
    if [ -f "$f" ]; then ok "$f"; else bad "missing $f (run from the project root)"; fi
done

if [ -f .env ]; then
    ok ".env exists ($PWD/.env)"
else
    bad '.env is missing in the project root'
    printf '  Fix: cp .env.example .env\n'
    printf '  Expected: %s/.env\n' "$PWD"
fi

if docker image inspect php:8.4.26-apache >/dev/null 2>&1; then
    ok 'upstream minimal target image php:8.4.26-apache is available'
else
    bad 'php:8.4.26-apache is not pulled; run: docker compose -f php2shell/docker/docker-compose.yml pull'
fi

if docker image inspect mariadb:10.11 >/dev/null 2>&1; then
    ok 'MariaDB image mariadb:10.11 is available'
else
    bad 'mariadb:10.11 is not pulled; run: docker compose -f compose.yaml -f compose.vuln.yaml pull db'
fi

if docker image inspect moodle-php-lab-moodle:8.3.35 >/dev/null 2>&1 && \
   docker image inspect moodle-php-lab-moodle:8.3.36 >/dev/null 2>&1; then
    ok 'Moodle 8.3.35 and 8.3.36 images are built'
else
    bad 'Moodle images are not built; run the two build commands in README.md'
fi

echo
if [ "$FAIL" -ne 0 ]; then
    printf '%sResult: FAIL.%s Required checks are not satisfied; do not start the lab yet.\n' "$C_RED" "$C_RESET"
    hint
    exit 1
fi
printf '%sResult: all checks passed.%s\n' "$C_GREEN" "$C_RESET"
if [ "$WARN" -ne 0 ]; then
    printf '%sNote: %s non-blocking warning(s).%s Review them if you have time; they do not block the Lab.\n' "$C_YELLOW" "$WARN" "$C_RESET"
fi

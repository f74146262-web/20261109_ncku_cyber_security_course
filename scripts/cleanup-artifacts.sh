#!/bin/sh
# Remove lab evidence files from the container web root and the shared loot/.
#
# This script removes only the fixed filenames used by this lab. It does not
# delete student-written example scripts in loot/ and does not reset Moodle
# data; run the reset-*.php examples first.
#
# Usage: sh scripts/cleanup-artifacts.sh
set -u

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT" || exit 1

COMPOSE="docker compose -f compose.yaml -f compose.vuln.yaml"
FAIL=0
ok()   { printf '  [PASS] %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; FAIL=1; }

CONTAINER=$($COMPOSE ps -q moodle 2>/dev/null || true)
if [ -z "$CONTAINER" ]; then
    bad 'Moodle container is not running'
    printf '  Start it, run this script, then stop it again:\n'
    printf '    %s up -d\n' "$COMPOSE"
    printf '    sh scripts/cleanup-artifacts.sh\n'
    exit 1
fi
ok "Moodle container: $CONTAINER"

# Fixed web-root artifacts created by the lab examples.
for name in p x b impact.txt grade-demo.txt good-hacker.webp; do
    if $COMPOSE exec -T moodle sh -c "rm -f '/var/www/html/$name'" >/dev/null 2>&1; then
        if $COMPOSE exec -T moodle sh -c "test ! -e '/var/www/html/$name'" >/dev/null 2>&1; then
            ok "removed /var/www/html/$name"
        else
            bad "/var/www/html/$name still exists"
        fi
    else
        bad "could not remove /var/www/html/$name"
    fi
done

$COMPOSE exec -T moodle rm -f /tmp/p >/dev/null 2>&1 || true

# Shared evidence files created by the exploit workflow.
for name in p1 c grade-progress.txt action demo-payload.php demo-proof.txt image-url; do
    rm -f "loot/$name"
    if [ ! -e "loot/$name" ]; then
        ok "removed loot/$name"
    else
        bad "loot/$name still exists"
    fi
done

# The PoC's default proof path, in case --proof-file was omitted.
rm -f php2shell/out/p1
if [ ! -e php2shell/out/p1 ]; then
    ok 'removed php2shell/out/p1'
else
    bad 'php2shell/out/p1 still exists'
fi

# Removing the image while the page HTML still links it leaves a broken
# image. Tell the student rather than silently editing Moodle data.
TOP=$($COMPOSE exec -T moodle php -r '
define("CLI_SCRIPT", true);
require("/var/www/html/config.php");
$v = get_config("core", "additionalhtmltopofbody");
echo is_string($v) ? $v : "";
' 2>/dev/null || true)
case "$TOP" in
    *good-hacker.webp*)
        printf '  [WARN] The Rickroll image is still configured; run reset-rickroll.php first.\n'
        ;;
esac

echo
if [ "$FAIL" -ne 0 ]; then
    echo 'Result: FAIL. Some artifacts could not be removed.'
    exit 1
fi
echo 'Result: PASS. Lab artifacts removed.'

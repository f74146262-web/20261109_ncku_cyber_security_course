#!/bin/sh
# Create the editable lab configs from their tracked templates.
#
# The generated files are ignored by Git. Existing files are never overwritten,
# so a student's edits survive this script and container restarts.
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT" || exit 1

for name in php.ini apache.conf; do
    target="labs/vuln/$name"
    template="labs/vuln/$name.template"
    if [ -f "$target" ]; then
        continue
    fi
    if [ ! -f "$template" ]; then
        echo "FAIL: missing template $template" >&2
        exit 1
    fi
    cp "$template" "$target"
    echo "Created $target from $template"
done

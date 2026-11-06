#!/bin/sh
set -eu

# The public URL is written into config.php during installation and reused on
# every start. Keep 127.0.0.1:PORT for local use, but let Codespaces or a
# reverse proxy supply its forwarded HTTPS URL through MOODLE_WWWROOT.
MOODLE_PORT=${MOODLE_PORT:-8080}
if [ -z "${MOODLE_WWWROOT:-}" ] && \
   [ -n "${CODESPACE_NAME:-}" ] && \
   [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
    # Codespaces exposes the service at:
    # https://<codespace>-<port>.<forwarding-domain>/
    MOODLE_WWWROOT="https://${CODESPACE_NAME}-${MOODLE_PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
fi
if [ -z "${MOODLE_WWWROOT:-}" ]; then
    MOODLE_WWWROOT="http://127.0.0.1:${MOODLE_PORT}"
fi
MOODLE_WWWROOT=${MOODLE_WWWROOT%/}
export MOODLE_PORT MOODLE_WWWROOT

if [ ! -f /opt/lab/flag.txt ]; then
    umask 027
    printf 'FLAG{%s}\n' "$(php -r 'echo bin2hex(random_bytes(16));')" > /opt/lab/flag.txt
    chown root:www-data /opt/lab/flag.txt
    chmod 640 /opt/lab/flag.txt
fi

chown www-data:www-data /var/www/moodledata /var/www/config
# fs.protected_symlinks=1 refuses to follow a root-owned symlink inside a
# world-writable sticky directory.  Moodle's front controller checks
# file_exists('./config.php') and would redirect to install.php forever.
chmod 0755 /var/www/html


# Moodle's generated config.php loads the core with __DIR__ . '/lib/setup.php'.
# After we move config.php to /var/www/config, __DIR__ becomes /var/www/config,
# so the require cannot find /var/www/config/lib/setup.php.
# Use an absolute path so the file works from either location.
fix_config_path() {
    file=$1
    [ -f "$file" ] || return 0
    sed -i \
        -e "s#require_once(__DIR__ \. '/lib/setup.php');#require_once('/var/www/html/lib/setup.php');#" \
        -e "s#require_once(dirname(__FILE__) \. '/lib/setup.php');#require_once('/var/www/html/lib/setup.php');#" \
        "$file"
}

# config.php keeps the public URL that Moodle redirects to. On an existing
# volume this must follow MOODLE_WWWROOT (for example a Codespaces forwarded
# URL); otherwise the browser is sent to 127.0.0.1 on the wrong machine.
fix_wwwroot() {
    file=$1
    [ -f "$file" ] || return 0
    sed -i "s|^\$CFG->wwwroot.*|\$CFG->wwwroot   = '${MOODLE_WWWROOT}';|" "$file"
}

# A public HTTPS URL usually means a TLS-terminating reverse proxy. Moodle
# needs both flags so it does not redirect forever between http and https, and
# so it trusts the proxy's host. Remove them again for local HTTP use.
fix_proxy_config() {
    file=$1
    [ -f "$file" ] || return 0
    case "$MOODLE_WWWROOT" in
        https://*)
            # Remove old copies first so the result is idempotent even when an
            # older entrypoint added only one flag or added duplicates.
            tmp="$file.tmp"
            grep -vF -e '$CFG->reverseproxy = true;' \
                -e '$CFG->sslproxy = true;' "$file" > "$tmp" || true
            # Insert after the generated $CFG initialization, not directly
            # after <?php: $CFG must exist before these assignments.
            line=$(grep -nF "require_once('/var/www/html/lib/setup.php');" "$tmp" | head -n 1 | cut -d: -f1)
            if [ -n "$line" ]; then
                head -n "$((line - 1))" "$tmp" > "$tmp.new"
                printf '%s\n' '$CFG->reverseproxy = true;' '$CFG->sslproxy = true;' '' >> "$tmp.new"
                tail -n "+$line" "$tmp" >> "$tmp.new"
            else
                line=$(grep -nF '$CFG = new stdClass();' "$tmp" | head -n 1 | cut -d: -f1)
                [ -n "$line" ] || line=1
                head -n "$line" "$tmp" > "$tmp.new"
                printf '%s\n' '$CFG->reverseproxy = true;' '$CFG->sslproxy = true;' '' >> "$tmp.new"
                tail -n "+$((line + 1))" "$tmp" >> "$tmp.new"
            fi
            mv "$tmp.new" "$file"
            rm -f "$tmp"
            chown www-data:www-data "$file"
            ;;
        *)
            if grep -qF -e '$CFG->reverseproxy = true;' \
                -e '$CFG->sslproxy = true;' "$file"; then
                tmp="$file.tmp"
                grep -vF -e '$CFG->reverseproxy = true;' \
                    -e '$CFG->sslproxy = true;' "$file" > "$tmp" || true
                mv "$tmp" "$file"
                chown www-data:www-data "$file"
            fi
            ;;
    esac
}


# The editable lab configs are generated from tracked *.template files and are
# ignored by Git. The directory is mounted at /opt/lab-vuln; create missing
# files here so a fresh clone works even if the student runs Compose directly.
prepare_lab_configs() {
    dir=/opt/lab-vuln
    [ -d "$dir" ] || return 0
    for name in php.ini apache.conf; do
        target="$dir/$name"
        template="$target.template"
        if [ ! -f "$target" ] && [ -f "$template" ]; then
            cp "$template" "$target"
            chmod 0666 "$target" 2>/dev/null || true
            echo "Created $target from template."
        fi
    done
    [ -f "$dir/php.ini" ] && cp "$dir/php.ini" /usr/local/etc/php/conf.d/zz-lab.ini
    [ -f "$dir/apache.conf" ] && cp "$dir/apache.conf" /etc/apache2/conf-enabled/zz-vuln.conf
}

prepare_lab_configs

# Request startup must see the PoC's 8M limit (stage 1).  Once /index.php has
# passed startup, config.php raises the limit so Moodle can render normally and
# the request reaches shutdown, where stage 3's fake destructor runs.
raise_moodle_memory() {
    file=$1
    [ -f "$file" ] || return 0
    grep -q 'PHP2Shell lab: raise memory' "$file" && return 0
    awk 'NR == 1 {
        print
        print "// PHP2Shell lab: raise memory after request startup."
        print "ini_set(\"memory_limit\", \"256M\");"
        next
    }
    { print }' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
    chown www-data:www-data "$file"
}


install_zh_tw() {
    [ -f /var/www/moodledata/lang/zh_tw/langconfig.php ] && return 0
    tmp=/tmp/zh_tw.zip
    if curl --fail --location --silent --show-error \
        "https://download.moodle.org/download.php/langpack/4.5/zh_tw.zip" -o "$tmp"; then
        php -r '$z=new ZipArchive; if ($z->open("/tmp/zh_tw.zip")===true) { $z->extractTo("/var/www/moodledata/lang"); $z->close(); }' || true
        rm -f "$tmp"
        # A partial extraction can leave a directory that Moodle cannot use.
        if [ ! -f /var/www/moodledata/lang/zh_tw/langconfig.php ]; then
            rm -rf /var/www/moodledata/lang/zh_tw
            echo "WARNING: zh_tw language pack extraction failed; continuing in English." >&2
            return 0
        fi
        chown -R www-data:www-data /var/www/moodledata/lang/zh_tw 2>/dev/null || true
    else
        echo "WARNING: could not download zh_tw language pack; continuing in English." >&2
        rm -f "$tmp"
    fi
}

if [ ! -f /var/www/config/config.php ]; then
    # Install Moodle with a normal memory budget.  The Apache workers later
    # run with the lab's 8M PoC precondition; installation must not inherit it.
    runuser -u www-data -- php -d memory_limit=512M -d max_input_vars=5000 \
        /var/www/html/admin/cli/install.php \
        --non-interactive \
        --agree-license \
        --lang=en \
        --wwwroot="${MOODLE_WWWROOT}" \
        --dataroot=/var/www/moodledata \
        --dbtype=mariadb \
        --dbhost=db \
        --dbname=moodle \
        --dbuser=moodle \
        --dbpass="${DB_PASSWORD}" \
        --fullname='NCKU Moodle' \
        --shortname='NCKU Moodle' \
        --adminuser=admin \
        --adminpass="${MOODLE_ADMIN_PASSWORD}" \
        --adminemail=admin@example.invalid
    fix_config_path /var/www/html/config.php
    raise_moodle_memory /var/www/html/config.php
    fix_wwwroot /var/www/html/config.php
    fix_proxy_config /var/www/html/config.php
    mv /var/www/html/config.php /var/www/config/config.php
else
    # Repair config.php in an existing volume created by an older entrypoint.
    fix_config_path /var/www/config/config.php
    raise_moodle_memory /var/www/config/config.php
    fix_wwwroot /var/www/config/config.php
    fix_proxy_config /var/www/config/config.php
fi

if [ ! -e /var/www/html/config.php ]; then
    ln -s /var/www/config/config.php /var/www/html/config.php
fi

install_zh_tw
if ! runuser -u www-data -- php /usr/local/bin/lab-ui; then
    echo "ERROR: Moodle baseline initialisation failed; refusing to report the lab as ready." >&2
    echo "Fix the error above, then restart the container. The site will not start with a partial baseline." >&2
    exit 1
fi

exec "$@"

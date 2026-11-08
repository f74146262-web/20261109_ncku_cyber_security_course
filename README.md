# 20261109 NCKU Cyber Security Course

This repository is the lab for the 2026 Fall NCKU Cyber Security course. You will start an isolated Moodle 4.5.15 / PHP 8.3.35 environment on your own computer, use the public PHP2Shell PoC to collect execution evidence, and then switch to PHP 8.3.36 for a patched comparison.

The site name and layout are for course practice. This is not the official NCKU Moodle; all courses, accounts, and grades are fictional test data.

You do not need to understand PHP memory corruption first, and you do not need to write an exploit. Follow the setup and exercises, then explain what you observed and what each result means in your writeup.

[Slide](https://moon-jam.github.io/20261109_ncku_cyber_security_course)

## What you will do

- **Before class**: install Docker, build both PHP versions, and pass the environment check.
- **In class**: start Moodle, run the PoC, and get the Flag.
- **Effects**: change and reset a fictional front-page name, a grade, and a good-hacker image.
- **After class**: design a fourth test effect and finish the writeup.

## Read this first

- Work only on the Lab at `127.0.0.1` on **your own computer**.
- Do not test the school website, external services, another student's computer, or any system without written permission.
- Do not change the port to `0.0.0.0`, and do not expose the service to your local network or the Internet.
- All grades, courses, and announcements are fictional test data. Reset every effect when you are done.
- The vulnerability is in the **PHP request startup**, not in Moodle itself.

## Before class

You need Docker, Docker Compose, Git, Python 3.9 or later, and curl. On Windows, work in a WSL2 Ubuntu terminal and put the project in `~/lab`, not in `/mnt/c/...`.

```sh
git clone https://github.com/moon-jam/20261109_ncku_cyber_security_course.git
cd 20261109_ncku_cyber_security_course
cp .env.example .env

# Pull the images used by Lab 0 and Moodle.
docker compose -f php2shell/docker/docker-compose.yml pull
docker compose -f compose.yaml -f compose.vuln.yaml pull db

# Build both Moodle PHP versions.
docker compose -f compose.yaml -f compose.vuln.yaml build
docker compose -f compose.yaml -f compose.vuln.yaml -f compose.patched.yaml build

sh scripts/prelab-check.sh
```

When it passes, you will see:

```text
$ sh scripts/prelab-check.sh
...
Result: all checks passed.
```

If only optional checks need attention, the result is still `all checks passed`, followed by a non-blocking warning note. A `[FAIL]` means the environment is not ready. `prelab-check.sh` checks both Moodle images, the PHP 8.4.26 target image, and the MariaDB image. The first build downloads the PHP base images and Moodle, so the time depends on your network and machine. See the platform notes and troubleshooting below.

## Start class

Work through the Labs in order. Do not start with the Moodle container.

1. **Lab 0: Upstream Minimal Target.** Follow [`labs/student/lab-0-minimal-target.md`](labs/student/lab-0-minimal-target.md). Start the PHP 8.4.26 target on port 8088, run the `official` profile PoC, confirm `uid=33(www-data)`, then stop it.
2. **Lab 1: Start and Configure Moodle.** Follow [`labs/student/lab-guide.md`](labs/student/lab-guide.md). Start Moodle with the starter settings, then edit `labs/vuln/php.ini` and `labs/vuln/apache.conf`. These two files are generated from `*.template` and are Git-ignored; your edits will not appear in `git status`.
3. **Labs 2–8.** Continue in [`labs/student/lab-guide.md`](labs/student/lab-guide.md): Lab 2 Read the PoC; Lab 3 Verify Remote Code Execution; Lab 4 Capture The Flag (CTF); Lab 5 Front-page Name; Lab 6 Fictional Grade; Lab 7 Good-hacker Image; and Lab 8 Patched PHP Comparison.

## Login information

- Administrator: user `admin`, password is `MOODLE_ADMIN_PASSWORD` in `.env`. The default is `ClassroomOnly-ChangeMe-2026`, for local practice only.
- Test student: user `p2s_student`, password `StudentOnly-2026`. This account is created by the Lab and is not a real student.
- `p2s_student` is seed data in the baseline. The baseline also contains the fictional `作業系統` (`OS`) course and a `Midterm` grade item at 30.00. The grade effect changes that grade to 100.00, and reset writes 30.00 back without deleting anything. If seed data is missing, restart the Moodle container so the initializer can restore it.

Do not use these default passwords on any real system.

## Course documents

1. [`labs/student/lab-0-minimal-target.md`](labs/student/lab-0-minimal-target.md): run the upstream PHP 8.4.26 minimal target and prove the PoC works before Moodle.
2. [`labs/student/lab-guide.md`](labs/student/lab-guide.md): from starting Moodle to RCE, the Flag, the three test effects, resets, and the 8.3.36 comparison.
3. [`labs/examples/README.md`](labs/examples/README.md): the front-page name, fictional grade, good-hacker image, and reset scripts.
4. [`labs/student/writeup-template.md`](labs/student/writeup-template.md): writeup format, grading, and the fourth effect.

## Utility scripts

**Instructor demo:** `scripts/instructor-demo.sh` is for demonstrations only, not student exercises. After starting Moodle, run:

```sh
sh scripts/instructor-demo.sh setup
```

This downloads and verifies the demo payload. The default URL is `https://s.xn--kst.tw/A`; use `DEMO_PAYLOAD_URL` to override it. Run the script with `--help` for available actions and options.

**Version switching and cleanup:**

```sh
sh scripts/switch-php.sh 8.3.35  # Vulnerable PHP
sh scripts/switch-php.sh 8.3.36  # Patched PHP
sh scripts/cleanup-artifacts.sh  # Remove Lab artifacts
```

## Scope of this Lab

| Component | Version |
|---|---|
| Moodle | 4.5.15 |
| PHP (vulnerable) | 8.3.35 |
| PHP (patched) | 8.3.36 |
| MariaDB | 10.11 |
| PoC | `3em0/php2shell`, fixed commit, MIT |

The Lab uses a single Apache prefork worker, `8M / 1000 / display_errors=On` for the `/index.php` request startup, and `config.php` raising the memory limit to `256M` before Moodle loads. These are the public PoC's reproduction conditions, not recommendations for a production Moodle.

A default production Moodle with 150 workers did not reproduce reliably in our tests, so this course does not use that setup as the exercise target. See "What this Lab does" in the Lab Guide for the exact boundaries.

## Safety and data

- Compose publishes Moodle only on `127.0.0.1`; MariaDB has no public port.
- The Lab does not use host networking, privileged containers, or a Docker socket mount.
- `compose.vuln.yaml` uses `seccomp=unconfined` and `/loot` uses `0777` only for this disposable local Lab: the former lets `setarch -R` pin the address space, and the latter lets `www-data` write shared proof. These are not production recommendations. Stop the container when you finish.
- The Flag is at `/opt/lab/flag.txt` inside the container, outside the web root. The goal is **execution evidence obtained over HTTP**, not reading the file directly from a Docker volume.
- `loot/` is a shared mount. Proof and temporary files there are not tracked by Git.
- Do not commit `.env`, files in `loot/`, logs, or any credentials.

## Platform notes

- **Windows (x86-64 only):** Use WSL2 (Ubuntu) with Docker Desktop's WSL integration enabled. Do not use Windows on ARM.
- **macOS (Apple Silicon):** Use Docker Desktop with Rosetta enabled, or OrbStack, to run `linux/amd64` containers.
- **Linux:** Install Docker Engine and Docker Compose.
- **GitHub Codespaces:** Run `sh scripts/codespace-up.sh` to configure and start Moodle. Keep the forwarded port **Private**.

## Troubleshooting

Start with the Lab's own check:

```sh
sh scripts/prelab-check.sh
sh scripts/wait-moodle.sh
sh scripts/env-check.sh
```

Common cases:

| Symptom | What to check |
|---|---|
| Docker daemon is not reachable | Start Docker Desktop/OrbStack, reopen the terminal, and run `docker version` |
| `docker compose: command not found` | Install the Compose plugin or use Docker Desktop |
| Port 8080 is in use | Change `MOODLE_PORT` in `.env`; update the URL in commands and the browser |
| Browser redirects to `http://127.0.0.1:8080` in Codespaces | Run `sh scripts/codespace-up.sh`; it sets `MOODLE_WWWROOT` to the current forwarded HTTPS URL and recreates Moodle |
| `Must use https address in wwwroot when ssl proxy enabled` | The Moodle config is stale or mixed. Run `sh scripts/codespace-up.sh`; do not edit the hosts file |
| `/index.php` returns 302 or 500 within 8 minutes | Moodle may still be installing; wait for `wait-moodle.sh` |
| Database connection failed | Check `dbhost`/`dbsocket` in `/var/www/config/config.php` and the Moodle logs. Try `down` then `up` before deleting volumes |
| `require_once(.../lib/setup.php)` | Old container config; rebuild the image and recreate the container |
| Repeated `heap leak missed` | Check PHP 8.3.35, the edited ini values, one worker, and `x86_64` |
| `CONTAINER` is empty | Start Moodle and use the full `-f compose.yaml -f compose.vuln.yaml` arguments |
| Stage 3 says `no proof yet` | Check `--proof-file`, the working directory, and whether the command writes a file |
| The patched version still succeeds | Confirm the running image and PHP version with `sh scripts/switch-php.sh 8.3.36` and `sh scripts/env-check.sh 8.3.36` |

### Browser redirects to 127.0.0.1

In Codespaces, Moodle still has `wwwroot=http://127.0.0.1:8080`. Run:

```sh
sh scripts/codespace-up.sh
```

It writes the current forwarded HTTPS URL to `.env`, recreates Moodle, and waits. Do not edit `/etc/hosts`; it cannot fix `wwwroot` or proxy flags.

For another reverse proxy, set `MOODLE_WWWROOT=https://<your-forwarded-host>` in `.env` and recreate Moodle. Local: leave it empty.

After setting it, `curl 127.0.0.1` may return `303` to the forwarded URL; this is expected. `wait-moodle.sh` and `env-check.sh` accept it; open the forwarded URL in the browser.

Do not run `docker compose ... down -v` to fix a normal startup problem. It deletes Moodle data, the baseline course, and the Flag. Use it only when you intentionally want an empty Lab.

If you need help, include your OS/CPU, Docker version, the failing command, the complete error, and what you already tried.

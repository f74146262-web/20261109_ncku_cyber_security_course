# php2shell (fixed course version)

This directory contains a fixed copy of `3em0/php2shell` so students can read and run a verified PoC without cloning the upstream repository separately.

## What this is

`php2shell` targets a request-startup issue in PHP 8.x with Apache prefork and mod_php. It uses state left behind by `session.upload_progress` across requests, performs a heap leak, leaks libphp, and forges a `HashTable` to call `zif_system` during shutdown.

The course target is not a default production Moodle. It is a local, isolated Moodle 4.5.15 + PHP 8.3.35 Lab. The reproduction conditions, expected output, and patched comparison are in [`labs/student/lab-guide.md`](../labs/student/lab-guide.md).

## Files

| File | Purpose |
|---|---|
| `exploit.py` | Main PoC; do not modify |
| `docker/offsets.py` | Reads symbol offsets from the local container's `libphp.so` |
| `LICENSE` | Original MIT license |
| `VENDORED.md` | Source, commit, license, and hashes |
| `out/` | Proof and offset output directory |

## Start with the arguments

```sh
python3 php2shell/exploit.py --help
```

Important arguments:

- `-u`: target URL. In this course it is `http://127.0.0.1:8080/index.php`.
- `--profile official83`: the PHP 8.3 profile.
- `--docker-container`: the local Moodle container ID, used to read `libphp.so`.
- `--proof-file`: proof file path, relative to the directory where you run the command.
- `-c`: command to run, limited to 14 bytes.
- `--fetch`: HTTP path used to read the proof after success.

## Do not

- Do not modify the exploit logic in `exploit.py`.
- Do not use it against the school, external services, or another student's computer.
- Do not treat `--docker-container` as a remote attack tool; it needs local Docker access.
- Do not treat the upstream README's claims as this course's test results. The verified results are in the Lab Guide.

## License

The upstream program is provided under the MIT license, copyright 3em0. The original license text is kept in `LICENSE`; see `VENDORED.md` for the source and commit.

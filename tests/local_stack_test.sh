#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
local_deploy_script="$project_root/dev/deploy.sh"
environment_example="$project_root/dev/.env.example"

[ ! -e "$project_root/compose.yml" ]
[ ! -e "$project_root/scripts/deploy.local.sh" ]

[ -x "$local_deploy_script" ]
[ -f "$environment_example" ]

expected_environment='TZ=America/Sao_Paulo
MYSQL_ROOT_PASSWORD=local-development-only
POSTGRES_PASSWORD=local-development-only'
actual_environment=$(grep -Ev '^[[:space:]]*(#|$)' "$environment_example")
[ "$actual_environment" = "$expected_environment" ]

temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
fake_bin="$temporary_directory/bin"
docker_log="$temporary_directory/docker.log"
mkdir "$fake_bin"

cat > "$fake_bin/docker" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$DEPLOY_TEST_DOCKER_LOG"
EOF
chmod +x "$fake_bin/docker"

PATH="$fake_bin:$PATH" DEPLOY_TEST_DOCKER_LOG="$docker_log" "$local_deploy_script"

expected_commands="info
compose -f $project_root/dev/compose.yml config --quiet
compose -f $project_root/dev/compose.yml up -d --wait
compose -f $project_root/dev/compose.yml ps"
[ "$(cat "$docker_log")" = "$expected_commands" ]

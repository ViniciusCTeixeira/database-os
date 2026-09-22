#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
production_compose="$project_root/production/compose.yml"
redis_dockerfile="$project_root/production/docker/redis/Dockerfile"
deploy_script="$project_root/production/deploy.sh"

[ -f "$production_compose" ]
[ -f "$redis_dockerfile" ]
[ ! -e "$project_root/compose.production.yml" ]
[ ! -e "$project_root/docker/redis/Dockerfile" ]
[ -x "$deploy_script" ]
[ ! -e "$project_root/scripts/deploy.sh" ]

grep -Fq 'name: databases-os' "$production_compose"
grep -Fq 'mysql:8.4.11' "$production_compose"
grep -Fq 'redis:7.4.11' "$production_compose"
grep -Fq '127.0.0.1:3306:3306' "$production_compose"
grep -Fq '127.0.0.1:6379:6379' "$production_compose"
grep -Fq '127.0.0.1:5432:5432' "$production_compose"
grep -Fq 'MYSQL_ROOT_PASSWORD:' "$production_compose"
grep -Fq 'REDIS_ROOT_PASSWORD:' "$production_compose"
grep -Fq 'POSTGRES_PASSWORD:' "$production_compose"
grep -Fq 'context: .' "$production_compose"
grep -Fq 'dockerfile: docker/redis/Dockerfile' "$production_compose"

if grep -Fq 'secrets:' "$production_compose" \
    || grep -Fq '_PASSWORD_FILE' "$production_compose"; then
    printf '%s\n' 'Produção deve usar senhas no arquivo de ambiente, sem Docker secrets.' >&2
    exit 1
fi

MYSQL_ROOT_PASSWORD=validation-mysql-password \
REDIS_ROOT_PASSWORD=validation-redis-password \
POSTGRES_PASSWORD=validation-postgres-password \
docker compose -f "$production_compose" config --quiet

grep -Fq 'docker_env_file="$environment_root/.env"' "$deploy_script"
grep -Fq 'compose_file="$environment_root/compose.yml"' "$deploy_script"
grep -Fq 'docker compose --env-file "$docker_env_file" -f "$compose_file" config --quiet' "$deploy_script"
grep -Fq 'docker compose --env-file "$docker_env_file" -f "$compose_file" up -d --build --wait' "$deploy_script"

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

grep -Fq 'dev/deploy.sh' "$project_root/README.md"
grep -Fq 'production/deploy.sh' "$project_root/README.md"
grep -Fq 'production/.env' "$project_root/README.md"

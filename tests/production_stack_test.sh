#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
production_compose="$project_root/compose.production.yml"
deploy_script="$project_root/scripts/deploy.sh"

[ -f "$production_compose" ]
[ -x "$deploy_script" ]

grep -Fq 'mysql:8.4.11' "$production_compose"
grep -Fq 'redis:7.4.11' "$production_compose"
grep -Fq '127.0.0.1:3306:3306' "$production_compose"
grep -Fq '127.0.0.1:6379:6379' "$production_compose"
grep -Fq '127.0.0.1:5432:5432' "$production_compose"
grep -Fq 'MYSQL_ROOT_PASSWORD:' "$production_compose"
grep -Fq 'REDIS_ROOT_PASSWORD:' "$production_compose"
grep -Fq 'POSTGRES_PASSWORD:' "$production_compose"

if grep -Fq 'secrets:' "$production_compose" \
    || grep -Fq '_PASSWORD_FILE' "$production_compose"; then
    printf '%s\n' 'Produção deve usar senhas no arquivo de ambiente, sem Docker secrets.' >&2
    exit 1
fi

MYSQL_ROOT_PASSWORD=validation-mysql-password \
REDIS_ROOT_PASSWORD=validation-redis-password \
POSTGRES_PASSWORD=validation-postgres-password \
docker compose -f "$project_root/compose.yml" -f "$production_compose" config --quiet

grep -Fq 'openssl rand -hex 32' "$deploy_script"
grep -Fq 'docker/.env' "$deploy_script"
grep -Fq 'mysql-os-data' "$deploy_script"
grep -Fq 'postgres-os-data' "$deploy_script"
grep -Fq 'docker compose --env-file "$docker_env_file"' "$deploy_script"

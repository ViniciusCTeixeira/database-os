#!/bin/sh
set -eu

environment_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
docker_env_file="$environment_root/.env"
compose_file="$environment_root/compose.yml"

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
    printf '%s\n' 'Docker Compose não está disponível para o usuário atual.' >&2
    exit 78
fi

if [ ! -f "$docker_env_file" ]; then
    for volume in mysql-os-data postgres-os-data; do
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            printf '%s\n' "O volume '$volume' já existe, mas $docker_env_file não foi encontrado." >&2
            printf '%s\n' 'Recupere as senhas atuais e crie production/.env manualmente; o deploy não substituirá credenciais de uma base existente.' >&2
            exit 78
        fi
    done

    if ! command -v openssl >/dev/null 2>&1; then
        printf '%s\n' 'OpenSSL é necessário para gerar as senhas iniciais.' >&2
        exit 78
    fi

    umask 077
    temporary_env_file=$(mktemp "$environment_root/.env.XXXXXX")
    {
        printf '%s\n' '# Gerado pelo production/deploy.sh. Não versione este arquivo.'
        printf 'MYSQL_ROOT_PASSWORD=%s\n' "$(openssl rand -hex 32)"
        printf 'REDIS_ROOT_PASSWORD=%s\n' "$(openssl rand -hex 32)"
        printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 32)"
    } > "$temporary_env_file"
    chmod 0600 "$temporary_env_file"
    mv "$temporary_env_file" "$docker_env_file"
    printf '%s\n' "Arquivo $docker_env_file criado com novas senhas. Guarde uma cópia protegida antes de continuar."
fi

if [ ! -r "$docker_env_file" ]; then
    printf '%s\n' "Arquivo de ambiente Docker não encontrado ou ilegível: $docker_env_file" >&2
    exit 78
fi

set -a
. "$docker_env_file"
set +a

for variable in MYSQL_ROOT_PASSWORD REDIS_ROOT_PASSWORD POSTGRES_PASSWORD; do
    case "$variable" in
        MYSQL_ROOT_PASSWORD) value="${MYSQL_ROOT_PASSWORD:-}" ;;
        REDIS_ROOT_PASSWORD) value="${REDIS_ROOT_PASSWORD:-}" ;;
        POSTGRES_PASSWORD) value="${POSTGRES_PASSWORD:-}" ;;
    esac
    if [ -z "$value" ]; then
        printf '%s\n' "A variável $variable está vazia em $docker_env_file." >&2
        exit 78
    fi
done

if ! docker network inspect system-os >/dev/null 2>&1; then
    docker network create system-os >/dev/null
fi

docker compose --env-file "$docker_env_file" -f "$compose_file" config --quiet
docker compose --env-file "$docker_env_file" -f "$compose_file" up -d --build --wait

printf '%s\n' 'Banco central disponível na rede system-os; as portas permanecem restritas ao loopback do host.'

#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

usage() {
    printf '%s\n' "Uso: $(basename "$0") <start|stop|pause> [all|mysql|redis|postgres]" >&2
}

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

service_from_target() {
    case "$1" in
        mysql) printf '%s\n' mysql-os ;;
        redis) printf '%s\n' redis-os ;;
        postgres) printf '%s\n' postgres-os ;;
        *) return 1 ;;
    esac
}

dev_environment_file="$project_root/dev/.env"
production_environment_file="$project_root/production/.env"
has_dev_environment=0
has_production_environment=0

[ -f "$dev_environment_file" ] && has_dev_environment=1
[ -f "$production_environment_file" ] && has_production_environment=1

case "$has_dev_environment:$has_production_environment" in
    1:0)
        environment_name=dev
        environment_root="$project_root/dev"
        environment_file="$dev_environment_file"
        ;;
    0:1)
        environment_name=production
        environment_root="$project_root/production"
        environment_file="$production_environment_file"
        ;;
    1:1)
        fail 'Ambiente ambíguo: dev/.env e production/.env existem. Execute o script no host do ambiente desejado.'
        ;;
    0:0)
        fail 'Ambiente não identificado: crie dev/.env ou production/.env antes de usar este script.'
        ;;
esac

compose_file="$environment_root/compose.yml"

run_compose() {
    docker compose --env-file "$environment_file" -f "$compose_file" "$@"
}

container_state() {
    service=$1
    container_id=$(run_compose ps --all --quiet "$service")

    if [ -z "$container_id" ]; then
        return 1
    fi

    docker inspect --format '{{.State.Status}}' "$container_id"
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage
    exit 64
fi

action=$1
target=${2:-all}

case "$action" in
    start|stop|pause) ;;
    *) usage; exit 64 ;;
esac

case "$target" in
    all) services='mysql-os redis-os postgres-os' ;;
    mysql|redis|postgres) services=$(service_from_target "$target") ;;
    *) usage; exit 64 ;;
esac

[ -f "$compose_file" ] || fail "Compose não encontrado: $compose_file"
[ -r "$environment_file" ] || fail "Arquivo de ambiente não encontrado ou ilegível: $environment_file"

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
    fail 'Docker Compose não está disponível para o usuário atual.'
fi

run_compose config --quiet

for service in $services; do
    if ! container_state "$service" >/dev/null; then
        fail "O serviço $service não foi criado. Execute $environment_name/deploy.sh primeiro."
    fi
done

for service in $services; do
    state=$(container_state "$service")

    case "$action:$state" in
        start:paused)
            run_compose unpause "$service"
            printf '%s\n' "$service retomado."
            ;;
        start:running)
            printf '%s\n' "$service já está em execução."
            ;;
        start:exited|start:created|start:dead)
            run_compose start "$service"
            printf '%s\n' "$service iniciado."
            ;;
        stop:paused)
            run_compose unpause "$service"
            run_compose stop "$service"
            printf '%s\n' "$service parado."
            ;;
        stop:running|stop:restarting)
            run_compose stop "$service"
            printf '%s\n' "$service parado."
            ;;
        stop:exited|stop:created|stop:dead)
            printf '%s\n' "$service já está parado."
            ;;
        pause:running|pause:restarting)
            run_compose pause "$service"
            printf '%s\n' "$service pausado."
            ;;
        pause:paused)
            printf '%s\n' "$service já está pausado."
            ;;
        pause:exited|pause:created|pause:dead)
            printf '%s\n' "$service não está em execução."
            ;;
        *)
            fail "Estado não suportado para $service: $state"
            ;;
    esac
done

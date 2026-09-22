#!/bin/sh
set -eu

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

container_state() {
    docker inspect --format '{{.State.Status}}' "$1" 2>/dev/null
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

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    fail 'Docker não está disponível para o usuário atual.'
fi

for service in $services; do
    if ! container_state "$service" >/dev/null; then
        fail "O container $service não existe. Execute o deploy do ambiente primeiro."
    fi
done

for service in $services; do
    state=$(container_state "$service")

    case "$action:$state" in
        start:paused)
            docker unpause "$service"
            printf '%s\n' "$service retomado."
            ;;
        start:running)
            printf '%s\n' "$service já está em execução."
            ;;
        start:exited|start:created|start:dead)
            docker start "$service"
            printf '%s\n' "$service iniciado."
            ;;
        stop:paused)
            docker unpause "$service"
            docker stop "$service"
            printf '%s\n' "$service parado."
            ;;
        stop:running|stop:restarting)
            docker stop "$service"
            printf '%s\n' "$service parado."
            ;;
        stop:exited|stop:created|stop:dead)
            printf '%s\n' "$service já está parado."
            ;;
        pause:running|pause:restarting)
            docker pause "$service"
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

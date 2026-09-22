#!/bin/sh
set -eu

environment_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
compose_file="$environment_root/compose.yml"

if ! docker info >/dev/null; then
    printf '%s\n' 'Não foi possível acessar o Docker. Verifique se o daemon está ativo e se seu usuário tem permissão.' >&2
    exit 1
fi

printf '%s\n' 'Validando a configuração local...'
docker compose -f "$compose_file" config --quiet

printf '%s\n' 'Subindo os serviços locais...'
docker compose -f "$compose_file" up -d --wait

printf '%s\n' 'Serviços locais:'
docker compose -f "$compose_file" ps

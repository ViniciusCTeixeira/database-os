#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
database_script="$project_root/database-os.sh"

[ -x "$database_script" ]

temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

create_fake_docker() {
    fake_bin=$1
    mkdir "$fake_bin"

    cat > "$fake_bin/docker" <<'EOF'
#!/bin/sh
set -eu

lookup_state() {
    service=$1
    previous_ifs=$IFS
    IFS=,
    set -- ${DATABASE_OS_TEST_STATES:-}
    IFS=$previous_ifs

    for pair in "$@"; do
        case "$pair" in
            "$service="*) printf '%s\n' "${pair#*=}"; return 0 ;;
        esac
    done

    printf '%s\n' missing
}

printf '%s\n' "$*" >> "$DATABASE_OS_TEST_LOG"

case "$1" in
    info)
        exit 0
        ;;
    inspect)
        container=''
        for argument in "$@"; do
            container=$argument
        done
        lookup_state "${container#container-}"
        ;;
    compose)
        compose_command=''
        service=''
        for argument in "$@"; do
            case "$argument" in
                ps|start|stop|pause|unpause) compose_command=$argument ;;
            esac
            service=$argument
        done

        if [ "$compose_command" = ps ]; then
            state=$(lookup_state "$service")
            if [ "$state" != missing ]; then
                printf 'container-%s\n' "$service"
            fi
        fi
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "$fake_bin/docker"
}

run_case() {
    environment=$1
    label=$2
    action=$3
    target=$4
    states=$5

    case_directory="$temporary_directory/$label"
    environment_directory="$case_directory/$environment"
    fake_bin="$case_directory/bin"
    docker_log="$case_directory/docker.log"
    mkdir -p "$environment_directory" "$case_directory/work"
    cp "$database_script" "$case_directory/database-os.sh"
    chmod +x "$case_directory/database-os.sh"
    : > "$environment_directory/compose.yml"

    printf '%s\n' 'MYSQL_ROOT_PASSWORD=test' > "$environment_directory/.env"

    create_fake_docker "$fake_bin"

    (
        cd "$case_directory/work"
        PATH="$fake_bin:$PATH" \
        DATABASE_OS_TEST_LOG="$docker_log" \
        DATABASE_OS_TEST_STATES="$states" \
        "$case_directory/database-os.sh" "$action" "$target" > "$case_directory/output"
    )

    printf '%s\n' "$docker_log"
}

dev_log=$(run_case dev start_mysql start mysql 'mysql-os=exited,redis-os=running,postgres-os=running')
grep -Fq "compose --env-file $temporary_directory/start_mysql/dev/.env -f $temporary_directory/start_mysql/dev/compose.yml start mysql-os" "$dev_log"

production_log=$(run_case production resume_redis start redis 'mysql-os=running,redis-os=paused,postgres-os=running')
grep -Fq "compose --env-file $temporary_directory/resume_redis/production/.env -f $temporary_directory/resume_redis/production/compose.yml unpause redis-os" "$production_log"

stop_log=$(run_case dev stop_paused stop postgres 'mysql-os=running,redis-os=running,postgres-os=paused')
grep -Fq "compose --env-file $temporary_directory/stop_paused/dev/.env -f $temporary_directory/stop_paused/dev/compose.yml unpause postgres-os" "$stop_log"
grep -Fq "compose --env-file $temporary_directory/stop_paused/dev/.env -f $temporary_directory/stop_paused/dev/compose.yml stop postgres-os" "$stop_log"

pause_log=$(run_case dev pause_all pause all 'mysql-os=running,redis-os=running,postgres-os=running')
grep -Fq "compose --env-file $temporary_directory/pause_all/dev/.env -f $temporary_directory/pause_all/dev/compose.yml pause mysql-os" "$pause_log"
grep -Fq "compose --env-file $temporary_directory/pause_all/dev/.env -f $temporary_directory/pause_all/dev/compose.yml pause redis-os" "$pause_log"
grep -Fq "compose --env-file $temporary_directory/pause_all/dev/.env -f $temporary_directory/pause_all/dev/compose.yml pause postgres-os" "$pause_log"

missing_directory="$temporary_directory/missing"
mkdir -p "$missing_directory/dev" "$missing_directory/work"
cp "$database_script" "$missing_directory/database-os.sh"
chmod +x "$missing_directory/database-os.sh"
: > "$missing_directory/dev/compose.yml"
printf '%s\n' 'MYSQL_ROOT_PASSWORD=test' > "$missing_directory/dev/.env"
create_fake_docker "$missing_directory/bin"

if (
    cd "$missing_directory/work"
    PATH="$missing_directory/bin:$PATH" \
    DATABASE_OS_TEST_LOG="$missing_directory/docker.log" \
    DATABASE_OS_TEST_STATES='mysql-os=missing' \
    "$missing_directory/database-os.sh" start mysql
) >"$missing_directory/output" 2>&1; then
    exit 1
fi
grep -Fq 'Execute dev/deploy.sh primeiro.' "$missing_directory/output"
if grep -Eq '^compose .* (start|stop|pause|unpause) ' "$missing_directory/docker.log"; then
    exit 1
fi

if "$database_script" restart mysql >"$temporary_directory/invalid-output" 2>&1; then
    exit 1
fi
grep -Fq 'Uso:' "$temporary_directory/invalid-output"

ambiguous_directory="$temporary_directory/ambiguous"
mkdir -p "$ambiguous_directory/dev" "$ambiguous_directory/production"
cp "$database_script" "$ambiguous_directory/database-os.sh"
chmod +x "$ambiguous_directory/database-os.sh"
: > "$ambiguous_directory/dev/.env"
: > "$ambiguous_directory/production/.env"

if "$ambiguous_directory/database-os.sh" start mysql >"$ambiguous_directory/output" 2>&1; then
    exit 1
fi
grep -Fq 'Ambiente ambíguo' "$ambiguous_directory/output"

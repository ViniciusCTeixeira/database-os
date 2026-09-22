#!/bin/sh
set -eu

root_password="${REDIS_ROOT_PASSWORD:-}"

if [ -z "$root_password" ]; then
    echo "REDIS_ROOT_PASSWORD is required." >&2
    exit 1
fi

umask 077
cat > /data/users.acl <<EOF
user default off
user root on >${root_password} ~* &* +@all
EOF

exec redis-server /usr/local/etc/redis/redis.conf

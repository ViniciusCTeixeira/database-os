FROM redis:7.4.11@sha256:c6eabf748fc7a61dbb5a705c78bcf3d6377b1127a97d0ce965c11c44ba46896f

COPY docker/redis/redis.conf /usr/local/etc/redis/redis.conf
COPY docker/redis/entrypoint.sh /usr/local/bin/databases-os-redis-entrypoint

RUN chmod 0755 /usr/local/bin/databases-os-redis-entrypoint

ENTRYPOINT ["/usr/local/bin/databases-os-redis-entrypoint"]

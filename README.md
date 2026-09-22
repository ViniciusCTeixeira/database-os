# databases-os

Serviços de dados compartilhados pelo servidor. O Compose de desenvolvimento continua em `compose.yml`; produção aplica `compose.production.yml` como override dele.

## Produção

Crie a rede compartilhada uma vez no host:

```sh
docker network create system-os
```

Execute `scripts/deploy.sh`. Em instalação nova, ele gera três senhas independentes, cria `docker/.env` com permissão `0600`, valida o Compose e sobe os serviços. Esse arquivo é exclusivo do Docker Compose e fica fora do Git.

Se os volumes MySQL ou PostgreSQL já existirem, o script exige `docker/.env` com `MYSQL_ROOT_PASSWORD`, `REDIS_ROOT_PASSWORD` e `POSTGRES_PASSWORD` preenchidos com as senhas atuais; ele não gera nem substitui credenciais.

Suba a pilha com:

```sh
scripts/deploy.sh
```

Os bancos entram na rede Docker externa `system-os` como `mysql-os`, `redis-os` e `postgres-os`. No host, somente os listeners de loopback são publicados: `127.0.0.1:3306`, `127.0.0.1:6379` e `127.0.0.1:5432`.

MySQL usa `root`; Redis desativa o usuário `default` e habilita somente a ACL administrativa `root`; PostgreSQL usa `postgres`. Essa escolha foi solicitada para centralização operacional e concede privilégios totais a qualquer aplicação que receba essas senhas.

Em volumes MySQL ou PostgreSQL já existentes, os valores em `docker/.env` devem ser as senhas que já valem no volume. As variáveis de inicialização só se aplicam a uma base vazia; altere a senha no banco antes do corte se for preciso alinhá-la ao `.env`.

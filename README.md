# databases-os

Serviços de dados compartilhados pelo servidor, separados por ambiente. Desenvolvimento e produção têm manifestos Compose, scripts de deploy e arquivos de ambiente próprios.

## Desenvolvimento local

Os arquivos de desenvolvimento ficam em `dev/`. Para ajustar as credenciais locais, copie o exemplo antes de subir a pilha:

```sh
cp dev/.env.example dev/.env
dev/deploy.sh
```

O script valida o Compose, sobe os serviços e espera os health checks. MySQL, Redis e PostgreSQL são publicados apenas no loopback local, respectivamente em `127.0.0.1:3306`, `127.0.0.1:6379` e `127.0.0.1:5432`.

## Produção

No servidor, execute:

```sh
production/deploy.sh
```

Na primeira instalação, o script cria `production/.env` com três senhas independentes, permissão `0600`, valida a configuração e sobe os serviços. Guarde uma cópia protegida desse arquivo: ele fica fora do Git.

Em uma instalação existente, mova o arquivo de credenciais antes do primeiro deploy após esta reorganização:

```sh
mv docker/.env production/.env
production/deploy.sh
```

Se os volumes `mysql-os-data` ou `postgres-os-data` já existirem e `production/.env` estiver ausente, o deploy para sem gerar novas credenciais. Recupere as senhas atuais e preencha o arquivo manualmente; variáveis de inicialização não alteram senhas já gravadas nos volumes.

Os bancos entram na rede Docker externa `system-os` como `mysql-os`, `redis-os` e `postgres-os`. No host, os listeners continuam restritos a loopback: `127.0.0.1:3306`, `127.0.0.1:6379` e `127.0.0.1:5432`.

MySQL usa `root`; Redis desativa o usuário `default` e habilita somente a ACL administrativa `root`; PostgreSQL usa `postgres`. Qualquer aplicação que receber essas senhas terá privilégios totais nos respectivos serviços.

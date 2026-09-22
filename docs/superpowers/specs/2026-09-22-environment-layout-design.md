# Separação dos ambientes de desenvolvimento e produção

## Objetivo

Organizar o repositório para que desenvolvimento e produção sejam ambientes independentes, cada um com seu próprio `compose.yml`, script de deploy e arquivo de ambiente. A separação deve manter os serviços, os nomes de volumes, a rede externa e a exposição de portas atuais.

## Estrutura de diretórios

```text
dev/
  compose.yml
  .env.example
  deploy.sh
  .env

production/
  compose.yml
  deploy.sh
  docker/redis/
    Dockerfile
    entrypoint.sh
    redis.conf

tests/
README.md
.gitignore
```

Os dois arquivos chamados `compose.yml` ficam em diretórios distintos. A raiz retém somente arquivos compartilhados: documentação, regras de Git e testes.

## Desenvolvimento

`dev/compose.yml` conterá a configuração local completa e será iniciado por `dev/deploy.sh`. O script verifica o acesso ao Docker, valida o Compose, executa `up -d --wait` e mostra o estado dos serviços. O `.env.example` e o `.env` atual passam para `dev/`; o arquivo real continua ignorado pelo Git.

## Produção

`production/compose.yml` será um manifesto completo que incorpora a configuração atualmente distribuída entre `compose.yml` e `compose.production.yml`. `production/deploy.sh` usa apenas esse manifesto, gera ou lê `production/.env`, valida a configuração e sobe os serviços com build e espera de saúde. A personalização de Redis fica em `production/docker/redis/`, permitindo que todos os artefatos exclusivos de produção permaneçam no mesmo diretório.

Os nomes atuais de containers, volumes, rede `system-os`, imagens, credenciais obrigatórias e portas de loopback serão preservados. O deploy de produção continua a não substituir credenciais quando os volumes de MySQL ou PostgreSQL já existirem.

## Migração e compatibilidade

Os comandos antigos na raiz deixam de ser documentados. Os novos pontos de entrada serão `dev/deploy.sh` e `production/deploy.sh`. A documentação explicará que instalações de produção existentes devem mover `docker/.env` para `production/.env` antes do primeiro deploy após a reorganização.

O `.gitignore` continuará ignorando qualquer `.env` e permitirá somente arquivos `.env.example`; portanto os dois diretórios ficam protegidos sem duplicar regras locais de Git.

## Validação

Os testes de desenvolvimento e produção serão atualizados para usar os novos caminhos e validar, com Docker simulado quando apropriado, os comandos de cada script. A validação final inclui sintaxe de shell, os dois testes de stack, renderização de ambos os Compose e `git diff --check`.

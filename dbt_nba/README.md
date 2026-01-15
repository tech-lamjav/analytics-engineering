# dbt NBA Project

## Configuração Local

O `profiles.yml` está localizado na raiz do projeto. Para rodar o dbt localmente, você precisa apontar para esse arquivo.

### Opção 1: Usar variável de ambiente (Recomendado)

Configure a variável de ambiente `DBT_PROFILES_DIR` apontando para a raiz do projeto:

```bash
export DBT_PROFILES_DIR=$(pwd)
```

Ou adicione ao seu `~/.zshrc` ou `~/.bashrc`:
```bash
export DBT_PROFILES_DIR=/Users/mateuskasuya/Documents/smartbetting/analytics-engineering
```

Depois disso, você pode rodar os comandos normalmente:
```bash
cd dbt_nba
dbt run
dbt test
dbt debug
```

### Opção 2: Usar flag --profiles-dir em cada comando

```bash
dbt run --profiles-dir .. --project-dir .
dbt debug --profiles-dir .. --project-dir .
```

### Verificar configuração

Para verificar se está lendo o arquivo correto:
```bash
dbt debug --profiles-dir .
```

Você deve ver algo como:
```
Using profiles dir at /Users/mateuskasuya/Documents/smartbetting/analytics-engineering
Using profiles.yml file at /Users/mateuskasuya/Documents/smartbetting/analytics-engineering/profiles.yml
```

## Recursos

- [Documentação dbt](https://docs.getdbt.com/docs/introduction)
- [Discourse](https://discourse.getdbt.com/)
- [Slack Community](https://community.getdbt.com/)

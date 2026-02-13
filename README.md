# Analytics Engineering - NBA Data Pipeline

Projeto de analytics engineering para transformação e modelagem de dados da NBA usando dbt (data build tool) e BigQuery, com deploy automatizado no Google Cloud Run.

## 📋 Visão Geral

Este projeto implementa um pipeline de dados completo para análise de estatísticas da NBA, incluindo:
- Transformação de dados brutos em modelos analíticos
- Dimensões e fatos para análise de apostas esportivas
- Processamento de estatísticas de jogadores, times e jogos
- Análise de lesões e impactos em performance
- Deploy automatizado no Cloud Run para execução agendada

## 🏗️ Arquitetura

```
Raw Data (GCS) → Staging (Views) → Intermediate (Views) → Marts (Tables)
```

- **Staging**: Limpeza e padronização dos dados brutos
- **Intermediate**: Transformações intermediárias e lógica de negócio
- **Marts**: Modelos finais para consumo (dimensões e fatos)

## 📁 Estrutura do Projeto

```
analytics-engineering/
├── dbt_nba/                    # Projeto dbt
│   ├── models/
│   │   ├── staging/           # Modelos de staging (views)
│   │   ├── intermediate/      # Modelos intermediários (views)
│   │   └── marts/             # Modelos finais (tables)
│   ├── dbt_project.yml        # Configuração do projeto dbt
│   └── packages.yml           # Dependências do dbt
├── profiles.yml                # Configuração de conexão BigQuery
├── Dockerfile                  # Imagem Docker para Cloud Run
├── build-and-push.sh          # Script de build e deploy
├── requirements.txt            # Dependências Python
└── README.md                   # Esta documentação
```

## 🚀 Configuração Local

### Pré-requisitos

- Python 3.13+
- dbt-core e dbt-bigquery instalados
- Acesso ao projeto GCP `smartbetting-dados`
- Autenticação gcloud configurada (`gcloud auth application-default login`)

### Instalação

1. **Clone o repositório** (se aplicável)

2. **Instale as dependências Python:**
   ```bash
   pip install -r requirements.txt
   ```

3. **Configure o dbt para usar o profiles.yml da raiz:**
   ```bash
   export DBT_PROFILES_DIR=$(pwd)
   ```

   Ou adicione ao seu `~/.zshrc` ou `~/.bashrc`:
   ```bash
   export DBT_PROFILES_DIR=/caminho/absoluto/para/analytics-engineering
   ```

4. **Instale as dependências do dbt:**
   ```bash
   cd dbt_nba
   dbt deps
   ```

### Executando Localmente

```bash
# Navegar para o diretório do projeto dbt
cd dbt_nba

# Verificar conexão
dbt debug

# Executar todos os modelos
dbt run

# Executar modelos específicos
dbt run --select staging.*
dbt run --select marts.*

# Executar testes
dbt test

# Gerar documentação
dbt docs generate
dbt docs serve
```

## ☁️ Deploy no Cloud Run

### Pré-requisitos

- Google Cloud SDK instalado e configurado
- Permissões para criar Cloud Run Jobs
- Artifact Registry configurado
- Service Account com permissões adequadas

### Permissões do Service Account

O service account usado no Cloud Run Job precisa das seguintes roles:

- `roles/bigquery.dataEditor` - Criar/atualizar tabelas e views
- `roles/bigquery.jobUser` - Executar queries no BigQuery
- `roles/bigquery.dataViewer` - Ler dados das tabelas fonte

**Ou use a role mais completa:**
- `roles/bigquery.user` - Inclui todas as permissões acima

### Build e Push da Imagem Docker

1. **Configure as variáveis de ambiente (opcional):**
   ```bash
   export GCP_PROJECT_ID=smartbetting-dados
   export GCP_REGION=us-east1
   export ARTIFACT_REGISTRY_REPO=dbt-nba-repo
   export IMAGE_NAME=dbt-nba
   export IMAGE_TAG=latest
   ```

2. **Execute o script de build e push:**
   ```bash
   chmod +x build-and-push.sh
   ./build-and-push.sh
   ```

   O script irá:
   - Configurar autenticação Docker com gcloud
   - Criar builder buildx para multiplataforma
   - Fazer build da imagem para `linux/amd64` (requerido pelo Cloud Run)
   - Fazer push para o Artifact Registry

### Configuração do Cloud Run Job

1. **Crie um Cloud Run Job** apontando para a imagem:
   ```
   us-east1-docker.pkg.dev/smartbetting-dados/dbt-nba-repo/dbt-nba:latest
   ```

2. **Configure o Service Account:**
   - Use um service account com as permissões BigQuery mencionadas acima
   - Configure no Cloud Run Job: `--service-account=SERVICE_ACCOUNT_EMAIL`

3. **Configure o comando (opcional):**
   - O comando padrão é: `dbt run --target prod`
   - Você pode sobrescrever no Cloud Run Job para executar comandos específicos

4. **Agende a execução (opcional):**
   - Use Cloud Scheduler para executar o job periodicamente

## 📊 Modelos de Dados

### Staging (`staging/`)

Modelos que fazem limpeza e padronização dos dados brutos:

- `stg_active_players` - Jogadores ativos da NBA
- `stg_games` - Informações dos jogos
- `stg_game_player_stats` - Estatísticas individuais dos jogadores por jogo
- `stg_player_injuries` - Informações de lesões
- `stg_player_props` - Props de apostas dos jogadores
- `stg_season_averages_general_base` - Médias gerais da temporada
- `stg_season_averages_general_advanced` - Estatísticas avançadas
- `stg_season_averages_shooting_by_zone` - Estatísticas de arremesso por zona
- `stg_team_standings` - Classificação dos times

### Intermediate (`intermediate/`)

Transformações intermediárias e lógica de negócio:

- `int_game_player_stats_pilled` - Estatísticas de jogos em formato longo
- `int_game_player_stats_not_played` - Jogos onde o jogador não participou
- `int_game_player_stats_last_game_text` - Texto descritivo do último jogo
- `int_games_teams_pilled` - Dados de jogos por perspectiva do time
- `int_season_averages_general_base` - Agregações de médias da temporada

### Marts (`marts/`)

Modelos finais para consumo analítico:

#### Dimensões

- `dim_players` - Dimensão completa de jogadores (com lesões e último jogo)
- `dim_stat_player` - Dimensão de estatísticas de jogadores (com ratings e análise de backup)
- `dim_teams` - Dimensão de times (com standings e próximos jogos)
- `dim_player_shooting_by_zones` - Estatísticas de arremesso por zona

#### Fatos

- `ft_games` - Fato de jogos
- `ft_game_player_stats` - Fato de estatísticas de jogadores por jogo

## 🔧 Configuração

### Profiles.yml

O arquivo `profiles.yml` na raiz do projeto contém as configurações de conexão:

- **dev**: Ambiente de desenvolvimento (usa OAuth local)
- **prod**: Ambiente de produção (usa OAuth via Application Default Credentials no Cloud Run)

### Variáveis de Ambiente

O projeto não requer variáveis de ambiente, pois os valores estão configurados diretamente no `profiles.yml`. Para desenvolvimento local, certifique-se de ter autenticação gcloud configurada.

## 🧪 Testes

Execute os testes do dbt:

```bash
cd dbt_nba
dbt test
```

Os testes incluem:
- Validação de unicidade
- Validação de não-nulos
- Testes customizados definidos nos arquivos `models.yml`

## 📚 Documentação

### Documentação online (GitHub Pages)

A documentação do dbt (linhagem, descrições dos modelos, testes) é publicada automaticamente no GitHub Pages a cada push em `main`/`master`. Acesse:

**[Ver documentação do dbt](https://tech-lamjav.github.io/analytics-engineering/)**

**Importante:** para o link mostrar os docs do dbt (e não este README), em **Settings > Pages** use **Source** = “Deploy from a branch”, **Branch** = `gh-pages`, **Folder** = `/ (root)`. Se estiver em `main`/`master`, o site exibirá o README.

Para catalog completo (metadados de colunas do BigQuery), adicione o secret `BIGQUERY_SA_KEY` em **Settings > Secrets and variables > Actions** com o JSON da service account (somente leitura no projeto/dataset).

### Documentação local

Gere e visualize a documentação localmente:

```bash
cd dbt_nba
dbt docs generate
dbt docs serve
```

Isso abrirá a documentação interativa no navegador com:
- Linhagem de dados
- Descrições dos modelos
- Testes e validações
- Dependências entre modelos

## 🔄 Workflow de Desenvolvimento

1. **Desenvolvimento Local:**
   - Faça alterações nos modelos SQL
   - Teste localmente com `dbt run --select <modelo>`
   - Execute testes com `dbt test`

2. **Commit e Push:**
   - Commit suas alterações
   - Push para o repositório

3. **Deploy:**
   - Execute `./build-and-push.sh` para build e push da imagem
   - A imagem será atualizada no Artifact Registry
   - O Cloud Run Job usará a nova imagem na próxima execução

## 🐛 Troubleshooting

### Erro de autenticação local

```bash
gcloud auth application-default login
```

### dbt não encontra o profiles.yml

Certifique-se de ter configurado:
```bash
export DBT_PROFILES_DIR=$(pwd)
```

### Erro de plataforma no Cloud Run

O script `build-and-push.sh` já configura o build para `linux/amd64`. Se ainda houver problemas, verifique se o buildx está configurado corretamente.

### Permissões no BigQuery

Verifique se o service account tem as roles necessárias:
- `roles/bigquery.user` (ou as roles específicas mencionadas acima)

## 📝 Recursos Adicionais

- [Documentação dbt](https://docs.getdbt.com/docs/introduction)
- [dbt BigQuery Setup](https://docs.getdbt.com/docs/core/connect-data-platform/bigquery-setup)
- [Cloud Run Jobs](https://cloud.google.com/run/docs/create-jobs)
- [BigQuery IAM Roles](https://cloud.google.com/bigquery/docs/access-control)

## 📄 Licença

[Adicione informações de licença se aplicável]

## 👥 Contribuidores

[Adicione informações de contribuidores se aplicável]

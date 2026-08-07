# Carimbo de procedência da imagem dbt, detectado fora dela

**Status:** accepted (2026-08-07)

A fase de guardas dbt (`dbt test --select tag:guarda`) roda da **mesma imagem Docker** que os
modelos que ela protege, então uma imagem velha causa o bug **e apaga o detector do bug** — a
guarda é estruturalmente cega para o modo de falha "a imagem não foi rebuildada". Decidimos
gravar um **carimbo de procedência** em cada Cloud Run Job (hash do conteúdo em disco das
paths que carregam comportamento) e conferi-lo de hora em hora por um detector que roda no
GitHub Actions, **fora da imagem**.

Este ADR fica na raiz e não em `dbt_futebol/docs/adr/` porque a decisão atravessa os dois
contextos (NBA e Futebol) e alcança o repo `data-engineering`.

## Vocabulário

Dois termos novos, deliberadamente **fora** de "guarda":

- **Procedência** — o que uma imagem em produção declara sobre a própria origem.
- **Deriva** — a condição de o que roda em produção não corresponder ao master.

"Guarda" neste repo já significa teste de dado dbt (`tag:guarda`). A lição inteira do
incidente é que **a guarda não consegue se vigiar**; reusar a palavra reimportaria a confusão
que abriu o buraco. Os termos moram aqui e não no `CONTEXT.md`, que é glossário de domínio.

## O que aconteceu (a evidência que motivou)

| pipeline | imagem em produção | commit que ficou fora | margem | tempo fora |
|---|---|---|---|---|
| futebol | 05/08 14:25:16 | 05/08 14:26 (`398b1d2`, fix do de-vig) | **70 segundos** | 2 dias |
| nba | 26/06 18:23:01 | 26/06 18:40 (`2f6263a`, DNP crítico + betting-math, 31 arquivos) | **17 minutos** | ~6 semanas |

Nos dois casos **o deploy aconteceu** — apenas *antes* do último commit. No futebol, o efeito
visível foi 924 linhas materializadas com `competition='unknown'` para a Ligue 1, e a fase de
guardas passou com `TOTAL=6` em vez de 13: as 7 tags que teriam pego exatamente isso estavam
no master e não na imagem. Sintoma e detector desligados pela mesma causa.

## Decisões

1. **O carimbo é o hash do conteúdo EM DISCO**, não `git rev-parse HEAD:<path>`. O
   `docker build` copia o disco, não o HEAD; um build com alteração não commitada — ou de um
   `.claude/worktrees/` numa branch, que é como este repo trabalha — carimbaria o master
   enquanto a imagem carrega outra coisa, mentindo na direção perigosa ("está fresco").
2. **Só as paths que carregam comportamento** (`models/`, `macros/`, `tests/`, `snapshots/`,
   `seeds/`, `dbt_project.yml`, `packages.yml`, `package-lock.yml`, `requirements.txt`,
   `profiles.yml`, Dockerfile). `analyses/`, `docs/` e `CONTEXT.md` vão para a imagem mas não
   mudam comportamento: nos 30 dias anteriores foram 116 toques em `models` contra 28 nessas
   três — hashear a pasta inteira renderia ~28 alarmes falsos/mês, e um detector que grita por
   `CONTEXT.md` é ignorado em duas semanas.
3. **O par `<path> <blob>` entra no hash, não só o blob.** No dbt o nome do arquivo É o nome
   do modelo: renomear sem mudar uma linha muda a tabela materializada.
4. **`LC_ALL=C` na ordenação.** O build roda em macOS e o detector em ubuntu-latest;
   collation diferente daria ordem diferente, hash diferente e vermelho permanente parecendo
   bug misterioso.
5. **O carimbo mora no job (env var), não como LABEL da imagem.** O que apodrece é o *digest
   fixado no job*, não a tag: o job resolve `:latest` para um digest no `jobs update` e as
   execuções herdam. O carimbo interroga a coisa certa, e o detector precisa só de
   `roles/run.viewer` — nunca lê o Artifact Registry.
6. **`gcloud run jobs update` foi dobrado para dentro do `build-and-push.sh`**, com
   `--update-env-vars` (não `--set-env-vars`, que apagaria variáveis futuras em silêncio).
   Build, digest e carimbo passam a sair do mesmo comando e não podem divergir.
7. **Fail-closed**: carimbo ausente ou ilegível é deriva. Um detector que fica quieto quando
   não sabe é indistinguível de um detector desligado — o defeito original.
8. **Sem janela de graça** entre merge e deploy. O modo de falha é "ninguém deploya"; graça é
   o mecanismo que transforma "nunca" em "ainda não". Falso positivo se apaga sozinho no ciclo
   seguinte.
9. **Cadência horária.** O job `dbt-futebol` roda ~96×/dia (odds é `*/15` e chama o job 3× por
   ciclo): o dano é contínuo, não diário. Horário limita a ~4 execuções ruins.
10. **O alarme não bloqueia merge.** A deriva só passa a existir *depois* do merge, e reprovar
    um PR por deriva pré-existente do master puniria o ator errado. O detector agendado falha
    alto; o e-mail diário carrega o token `[DERIVA]` no assunto como rede de segurança.

## Opções consideradas e rejeitadas

- **Job dbt deployar `--source`, como os 13 serviços Cloud Run.** *Rejeitada.* Era a
  recomendação inicial, e a medição a derrubou: nos dois incidentes **o deploy aconteceu**,
  só que antes do último commit — `--source` numa linha teria produzido o mesmo resultado. Os
  "2 dias" e "6 semanas" são latência de *detecção*, não atrito de *deploy*. Além disso os
  serviços da NBA, que **são** `--source`, estavam 6 semanas defasados na mesma data. A
  ergonomia que essa opção comprava veio de graça na decisão 6. **Não re-propor sem primeiro
  refutar a tabela de margens acima.**
- **Auto-deploy no merge.** *Rejeitada por ora.* Várias sessões mergeiam no master em
  paralelo; produção passaria a seguir o master sem ninguém no circuito.
- **Detector comparando `updateTime` do Artifact Registry com a hora do último commit.**
  *Rejeitada.* É proxy de timestamp, e margens de 70 segundos e 17 minutos ficam exatamente na
  resolução em que um proxy desses quebra. O carimbo compara conteúdo com conteúdo.
- **Checar o `TOTAL` da linha `Done.` da fase de guardas contra um número esperado.**
  *Rejeitada como detector.* Exige um esperado que apodrece a cada guarda nova; e o carimbo
  já o subsume — carimbo batendo implica conjunto de tags certo. O `TOTAL` fica no e-mail
  apenas como contexto descritivo.

## Consequências

- Enquanto um job não for rebuildado com o script novo, ele aparece **vermelho** — é o
  fail-closed funcionando, não um defeito.
- O `dbt_nba` **não tem nenhum teste `tag:guarda`** (os 10 são todos do futebol). O carimbo é
  a única cobertura que a NBA tem contra esta classe.
- Os serviços Cloud Run do `data-engineering` sofrem da mesma deriva e ainda **não** estão
  cobertos; o detector já é uma tabela declarativa de alvos para recebê-los.

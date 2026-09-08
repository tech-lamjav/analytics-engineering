---
status: accepted
---

# O regime do insumo é catálogo, não coluna de mart

A issue #148 (ClickUp "O mart não diz qual insumo e qual janela cada premissa usou") pedia,
literalmente, colunas novas em mart/funil (`insumo_recorte`, `insumo_escopo`) para responder sob
qual janela cada premissa foi medida. Decidimos o oposto: a resposta vira uma quarta chave no
catálogo `futebol_insumos_premissa()` (macros/premissas_insumos.sql), ao lado de `modelo`,
`nome` e `insumos` — nenhuma tabela materializada muda.

## Por que catálogo, e não coluna

`pit_escopo`/`pit_recorte` (ADR 0007/0010) são **vars do dbt**: constantes para o build inteiro,
não dado que varie linha a linha. Em produção elas são sempre `todas`/`ultimos_10`. Uma coluna de
mart que repetisse esse valor em toda linha não estaria publicando uma medição — estaria
publicando uma constante disfarçada de coluna, materializada milhares de vezes por nada. E nem
toda premissa segue esse eixo: `superioridade_tabela` (ADR 0008) e `h2h_favoravel` são isentas por
desenho, e várias outras têm fonte de histórico própria (`margin_stats` no Handicap, `last5` em
BTTS/Gols, `team_hist` na Dupla Chance) cuja relação com o eixo já está documentada em prosa, na
docstring de cada um dos 5 modelos. O fato de "qual janela" já era conhecido — só não estava
formalizado num lugar consultável.

## Por que por insumo, e não por premissa

A tentação óbvia era um regime por premissa. Quebra em `lado_coberto_forte` (Dupla Chance): reusa
`forca_mismatch` (segue o eixo) **e** `superioridade_tabela` (isenta do eixo) do 1X2 — a mesma
premissa, dois regimes diferentes dependendo do insumo. `regimes` é um dict `{nome_do_insumo:
regime}`, chaveado pelo nome — não embutido dentro de cada item de `insumos`, porque
`futebol_premissas_cegas` (macros/premissas_sem_dado.sql) usa `i is mapping` para distinguir
insumo condicional de simples; transformar todo insumo simples num dict quebraria essa distinção
em silêncio, e essa entrega não tinha motivo para tocar o contador de cegueira.

## Os quatro regimes, e uma correção que só apareceu lendo o código

`pit`, `local_fixo`, `sempre_competicao`, `sem_recorte`. A definição original de `local_fixo` na
spec (#148) era "últimos 5 jogos, ex.: historico_btts, invicto_recente" — **errada**. Lendo as
docstrings dos 5 modelos com atenção: todo insumo em forma de "últimos 5" (last5_desc,
historico_btts/seco, historico_over/under, invicto_recente) **é escopado por competição antes do
corte de 5** — ele se move se `pit_escopo` mudar, mesmo que `pit_recorte` sature nele (5 é
subconjunto de 10 em qualquer ordem, então trocar temporada→ultimos_10 não o move). A pergunta
certa para `pit` é "se move com **algum** dos dois eixos", não "com os dois" — e sob essa leitura
nenhum dos insumos "últimos 5" é `local_fixo`. Hoje só um insumo qualifica de fato:
`h2h_favoravel` (`h2h_total`/`s_wins`) — fact_h2h "já cruza campeonatos hoje"
incondicionalmente, e não tem noção de recorte de contagem nenhuma, só quantas vezes os dois times
já se enfrentaram. `local_fixo` fica no enum mesmo com uma única instância hoje: é uma resposta
legítima que uma premissa futura pode dar, e o enum fechado existe para que essa resposta continue
disponível sem precisar de outro ADR.

## Por que não existe guarda de dado (`tag:guarda`) para isto

A spec original (#148) propunha uma guarda de dado espelhando `assert_premissas_insumo_declarado`.
Não foi criada. A validação de `regimes` roda **dentro** de `futebol_insumos_premissa()`, como
`exceptions.raise_compiler_error`, incondicionalmente, para qualquer consumidor — os 5 modelos de
premissa, a guarda de insumo declarado, o contador de cegueira. Um insumo sem regime ou com regime
fora do enum já quebra `dbt compile`/`dbt parse`, antes de existir dado para uma guarda de dado
examinar. Uma guarda de dado aqui nunca conseguiria ficar vermelha independentemente — o compile
já teria falhado primeiro — e isso é exatamente a "guarda infalsificável" que o próprio cabeçalho
de `assert_premissas_insumo_declarado` avisa para não criar (ela ensina a ignorar as outras).
Validação em compilação é estritamente mais forte aqui: roda mais cedo, e roda sempre, mesmo sem
`dbt test`.

## O que a validação garante, e o que ela nunca poderia garantir

Ela garante FORMA: todo insumo de premissa/penalidade tem um valor do enum em `regimes`. Ela
não garante, e não tem como garantir, que esse valor continua **verdade** sobre o SQL de hoje —
igual `aplicavel` e `insumos` não-vazio, desde a #39, também nunca verificaram a semântica do que
declaram. Se `int_futebol_team_form_pit.sql` mudar de um jeito que faça `s_rank` passar a seguir
o eixo (hoje `sempre_competicao`, ADR 0008), `dbt compile`/`dbt test` continuam verdes sobre um
catálogo que virou documentação falsa — a mesma classe de deriva silenciosa que fez o front
divergir do modelo por 11 dias e motivou a #148 originalmente. Não existe verificação automática
possível aqui sem reimplementar a lógica de escopo/recorte numa segunda linguagem só para
comparar contra a primeira, o que custaria mais do que o problema que resolveria. Manter
`regimes` correto é disciplina de quem edita os 5 modelos de premissa — a mesma disciplina que já
vale para as outras três chaves — não algo que este ADR converte em garantia automática.

## O que esta decisão NÃO faz

**Não publica valores por linha.** Saber que `superioridade_xg` segue `pit` não diz que o Goiás ×
Fortaleza mediu 1,49 contra 0,95 — só diz sob qual regime esse número foi calculado. Publicar o
valor em si toca o funil append-only (ADR 0011) e é trabalho separado, deliberadamente não
ticketado, pendente de decisão do Victor sobre custo e mercado inicial.

**Não muda o front.** `prop-play-predictor` continua sem ler nada disto — é o próximo ticket, na
quadra do Victor, só depois da decisão acima.

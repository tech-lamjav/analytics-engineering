---
status: accepted
---

# O histórico do produto é point-in-time no apito

O board não expurga. `fact_value_opportunities` é reconstruída inteira a cada execução e não
tem filtro de data nem de status: a linha de um jogo que já terminou continua sendo reavaliada
e reemitida enquanto os modelos de premissa e o de-vig continuarem produzindo-a. Medido em
17/08/2026, o board tinha **121 linhas e apenas 2 de jogo futuro**, a mais velha de **19/06**.

Isso não é só sujeira de análise. O app **depende** do entulho, em duas telas:

- `FutebolOportunidades.tsx` monta o stepper de dias com comentário literal `board = passado +
  presente` e renderiza a aba **Histórico** com acerto/erro lendo `get_futebol_value_board()`,
  que não filtra data nenhuma.
- `FutebolJogo.tsx` renderiza um bloco chamado **"registro pós-jogo"** para fixture encerrada,
  alimentado por `get_futebol_fixture_value()` — o mart de novo.

E o que essas telas mostram não é o que foi publicado. **97% das versões do
`fact_value_opportunities_hist` (14.946 de 15.452) nasceram depois do apito**, em média 668 h
— 28 dias — após o jogo. Pior: das 82 chaves cujo jogo aconteceu depois da estreia do
snapshot, **só 45 tinham versão viva no apito**. As outras 37 entraram no board **depois** da
partida. O produto contabiliza acerto e erro de palpite que ninguém podia ter feito.

O mecanismo de saída de hoje é o acaso: das 89 chaves que já morreram, **54 morreram depois do
apito, em média 464 h (19 dias) depois** — por churn de recomputação, não por decisão.

Decidimos duas coisas, e elas são uma só vista de dois lados. **O board é a janela do que ainda
dá para apostar**: o mart deixa de emitir a linha que saiu dessa janela. E **o passado é servido
pelo `hist`, na versão viva no apito** — a nota que existia quando dava para apostar, e nenhuma
outra.

## Expurgar não é apagar

O mart é `materialized='table'` e reconstruído do zero a cada execução. "Expurgo" aqui é a linha
**deixar de ser emitida**, nunca um `DELETE`: o `hist`, com `invalidate_hard_deletes`, fecha a
versão e a guarda para sempre. O nome é o que já circula com o Victor e por isso fica — mas
quem for procurar a exclusão no código não vai encontrar, e é de propósito.

A distinção importa por um segundo motivo, maior: ela impede que alguém "conserte" o funil da
A7 por analogia. A ADR 0006 decidiu o oposto para o funil, explicitamente — *"jogo encerrado
também continua no universo, e tem que continuar: é ele que responde a pergunta que justifica
esta decisão inteira — quanto rendeu a faixa que a gente descartou."* Os dois trabalhos puxam
para lados opostos porque respondem a perguntas diferentes:

| | guarda o quê | para quem |
| --- | --- | --- |
| **board** | o que é apostável **agora** | o app, tela ao vivo |
| **`hist`** | o que era apostável **no apito** | o app, tela de histórico |
| **funil** (A7) | tudo que foi avaliado, inclusive o rejeitado | análise, só BigQuery |

E fica registrado desde já, para a A7 não reabrir: **quando o board passar a ler o funil, o
histórico de serving continua sendo o `hist`.** O funil não serve o app.

## Point-in-time estrito, e o que isso custa

A leitura é `dbt_valid_from <= kickoff < dbt_valid_to`, **sem tolerância**. O snapshot roda por
dois caminhos — no poll de odds quando entrou preço novo, e uma vez de manhã antes do alerta
das 10h — então a foto existe quando houve preço, não a cada 15 minutos. Uma versão de `t15m`
cujo snapshot caia alguns minutos depois do apito é perdida, e a tela mostra a foto da `t1h`.

Aceitamos esse erro porque ele é **sempre para o lado conservador**: mostra uma foto mais
antiga, nunca uma nota nascida depois de a bola rolar. A `janela_usada` vai junto na resposta,
então a tela diz de que momento é a foto em vez de fingir que é sempre o fechamento. Uma
tolerância de N minutos recuperaria algumas linhas e abriria, pela mesma fresta, a porta que
esta decisão inteira existe para fechar.

O preço é visível e precisa ser dito antes de mexer: **o Histórico encolhe para 31 fixtures e
45 linhas** em todo o período. As 128 chaves de jogo anterior à estreia do snapshot (27/07) não
têm PIT e não voltam. Carimbar o board de hoje como se fosse histórico foi considerado e
**rejeitado** — seria gravar como registro justamente as 37 linhas que nasceram depois do jogo,
transformando o defeito em fonte.

## A fronteira do expurgo é o status, não o relógio

Expurgam: `FT`, `AET`, `PEN`, `CANC`, `ABD`, `AWD`, `WO` e os status ao vivo — não se aposta
pré-jogo com a bola rolando. **Sobrevivem `PST`, `SUSP` e `INT`**: kickoff no passado com jogo
ainda por acontecer é oportunidade legítima, e um corte por relógio a mataria. A rede para o que
passou do kickoff e nunca recebeu status final é **kickoff + 24 h**, em `var`
(`expurgo_carencia_horas`) — ela é um parâmetro da qualidade da coleta de placar, que é a [C] e
vai mudar.

Isso amarra o board à coleta de placar: **uma dependência [A]→[C] a mais**, além da que a ADR
0005 já registrou para a guarda do denominador.

O mart passa a juntar `fact_fixtures` para enxergar status e kickoff, e **não expõe nenhuma
coluna nova**. Coluna nova em tabela sincronizada exige migração no Postgres antes do deploy da
imagem, senão o parity aborta as 21 tabelas — e o ganho seria conveniência de quem já junta
`fact_fixtures` de qualquer jeito.

## A ordem de entrega é parte da decisão

Expurgar primeiro esvazia o Histórico e o stepper **em silêncio**: o `check_schema_parity`
passa, as duas RPCs devolvem 200 e a tela fica vazia. É exatamente a falha de 07/08 e 10/08
descrita no `contrato-serving-rpcs.md`. Então:

1. **RPC nova** `get_futebol_value_history(p_from date, p_to date)` — mesmas colunas de
   `get_futebol_value_board` (o front reaproveita o tipo inteiro), grão de uma linha por
   `opportunity_key`, na versão viva no apito. E o corpo de `get_futebol_fixture_value` passa a
   cair no PIT **quando o kickoff já passou** — não quando o jogo terminou, senão a tela do jogo
   fica vazia durante as duas horas de bola rolando, que é quando mais gente a abre.
2. **Front** lê o Histórico da RPC nova, para de assumir `board = passado + presente`, e **une
   as duas fontes no dia corrente** — senão o jogo das 16h some da tela às 16h05 e só reaparece
   no dia seguinte.
3. **Expurgo no mart**, com as duas guardas.

Cada passo é reversível sozinho e nenhum ponto intermediário deixa tela vazia. A migração do
Postgres vai antes de qualquer deploy de imagem, e `get_futebol_value_board` **não é alterada**
— mudar o `RETURNS TABLE` exigiria `DROP FUNCTION`.

Com isto, o `hist` deixa de ser "lido por nenhuma RPC" no `contrato-serving-rpcs.md`: o grão
dele vira contrato de serving.

## As duas guardas, e por que uma não basta

**Guarda 1** — linha com status terminal (ou kickoff + carência) no mart: qualquer linha é
vermelho. Ela prova que o expurgo acontece.

**Guarda 2** — chave **aberta** no `hist` que não existe no mart: vermelho. Ela prova que nada
evapora sem carimbo, que é o que impede o expurgo de virar perda silenciosa. Roda na fase de
guardas, depois do snapshot, nunca entre o mart e ele.

As duas com `tag:guarda` — é a única seleção que o agendado executa, e teste em dbt só alarma
por esse caminho (`reference_dbt_tests_nao_rodam_no_agendado`).

## O que esta decisão NÃO conserta

**Não conserta a churn.** São 15.452 versões para 210 chaves, ~73 por chave. O expurgo mata a
parte que vem de reavaliar defunto 96×/dia, mas o resíduo é premissa que não é reprodutível
entre builds (issue #78, `superioridade_xg`) — defeito separado, que fica com número em vez de
discussão: o baseline desta sessão é congelado no ticket e remedido **7 dias** depois, com alvo
declarado de **zero versão nova pós-apito**.

**Não poda o `hist`.** São 6 MB, e podar apagaria justamente a evidência de que o defeito
existiu. Retenção declarada só quando houver número — a mesma regra que a ADR 0006 aplicou ao
funil.

**Não cria histórico onde não houve.** O produto vai mostrar menos: 31 fixtures. É a primeira
vez que ele mostra a verdade.

## A armadilha de validação

`dev` e `prod` do `profiles.yml` apontam para o **mesmo** dataset `futebol`. Rodar `dbt run` do
mart na máquina **é** produção, e o sync leva para o app em até uma hora. A validação é por
`dbt compile` + `bq query` sobre o SQL compilado — conta as linhas que sairiam sem escrever
nada. Se for preciso materializar para conferir, vai para **dataset próprio**, como a ADR 0007
fez na task [F].

## Interação com a #40

A issue #40 quer gravar no board a **janela de detecção** — a janela mais cedo em que a linha
passou. Esse número só existe no `hist`, que é a fonte que esta decisão promove a leitor de
produto. **Esta entrega vai antes, e a #40 herda a leitura PIT** em vez de implementar a mesma
consulta uma segunda vez. Ela também acrescenta coluna ao mart, o que exige a migração do
Postgres que esta entrega deliberadamente evitou.

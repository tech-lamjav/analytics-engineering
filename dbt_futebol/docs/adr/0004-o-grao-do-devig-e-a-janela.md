---
status: accepted
---

# O grão do de-vig é a janela, e o multiplicador não é ganho de amostra

O `int_futebol_odds_devig` resolvia cada linha para **uma** janela — a mais recente disponível,
via `QUALIFY window_priority = MAX(...)` — e descartava as outras duas. Decidimos que a janela
passa a fazer parte da chave: o grão vira `(fixture, market, outcome, line, janela)`, e quem
escolhe qual janela vale é o consumidor, não o de-vig.

O board continua com **uma linha por linha**, avaliada na janela corrente, e ganha
`janela_deteccao` — a janela mais cedo em que a linha passou no gate. Oportunidade que perdeu
edge sai do board: preço que o usuário não consegue mais pegar não é oportunidade, é ruído com
carimbo de oportunidade. O histórico do que foi anunciado já tem lugar próprio no snapshot
`fact_value_opportunities_hist`.

## O que esta decisão NÃO compra

O ticket de origem justificava a mudança por multiplicar a base de medição: 21.407 linhas
únicas contra 60.818 combinações de linha com janela, um multiplicador de 2,84, e daí "quase
triplica a base, e a amostra é o gargalo de toda a investigação".

**O multiplicador é real e a conclusão é falsa.** No recorte liquidado são 19.649 linhas e
56.440 pares linha×janela — sobre **179 jogos, antes e depois**. As três janelas de uma linha
são três preços do mesmo palpite, liquidados pelo mesmo placar. Nos Testes 3 e 4 isso é apostar
três vezes na mesma partida: o ROI esperado não se move e o intervalo de confiança encolhe por
√3 sem que tenha entrado informação nenhuma.

Esse é precisamente o mecanismo que a ADR 0001 foi escrita para impedir — "amostra curta
fabrica sinal" — e ela já havia nomeado o gargalo real: *"o gargalo passa a ser a task C2
(ampliar a coleta de odds)"*, que é coletar mais **jogos**, não mais fotos dos mesmos jogos.
Registrar isto aqui é metade do propósito desta ADR: sem o registro, o 2,84× volta pela porta
dos pesos na próxima vez que alguém precisar de um n maior.

Portanto: **os Testes 2, 3 e 4 seguem com uma observação por linha**, com a janela fixada antes
de olhar resultado.

## O que ela compra

Uma pergunta que hoje não dá nem para formular: **o edge de t24h prevê melhor ou pior que o de
t15m?** É a pergunta de CLV, e é ela que decide se alertar cedo é virtude ou armadilha. Há
6.885 linhas com as duas janelas para respondê-la.

O tamanho do que está em jogo: recomputando o gate de valor por janela nos mercados 1/4/5,
passam **931** linhas em t15m, **1.350** em alguma janela, e **368 passam em t24h e já não
passam em t15m**. Essas 368 são exatamente as linhas em que o mercado se moveu **contra** nós
até o fechamento — CLV negativo, que a literatura trata como o sinal mais confiável de que a
aposta era ruim. Podem ser a maior descoberta da fila ou a maior armadilha dela, e hoje não
temos como saber qual.

## Sobre "o alerta pode sair mais cedo"

Não é o que esta mudança faz, e vale registrar porque o ticket afirmava o contrário. Quando um
jogo está a 24h do apito, a única janela que existe para ele é t24h; o `QUALIFY` escolhe t24h
por falta de alternativa, o mart reconstrói a cada ~15 minutos e o board **já publica ali**. O
que se perdia era o registro depois do jogo, não o alerta.

Quem faz o alerta sair mais cedo é ampliar o horizonte de coleta de odds, que hoje para em 24h
por causa da banda `(1320, 1440)` — escolha nossa, não limite da fonte: a API entrega 12–13
casas, Pinnacle inclusa, a 147h do apito.

## Alternativas consideradas

- **Colunas por janela na mesma linha** (`edge_t24h`, `edge_t1h`, `edge_t15m`, …). Rejeitada:
  congela o conjunto de janelas no schema. Acrescentar uma janela passa a exigir cinco colunas
  novas em cada modelo a jusante — e a próxima janela já está decidida.
- **Trocar "mais recente" por "mais cedo que passou"** no próprio `QUALIFY`. Rejeitada por ser
  circular: saber se a janela passou depende de `best_odd`, `n_casas` e do de-vig, que só
  existem *depois* de escolher a janela. Avaliar as três é pré-requisito, não alternativa.
- **Board também por janela**, deixando o agrupamento para o front. Rejeitada: quebraria
  `opportunity_key` do snapshot, triplicaria o que o sync materializa no Postgres, e empurraria
  para o front uma decisão de produto — qual das três mostrar.
- **Board segurando a oportunidade morta até o apito**, com odd e edge congelados na detecção.
  Rejeitada: exibe um preço que já não existe. A leitura literal de "publicar uma vez e
  acompanhar dali" custaria mostrar 2,35 onde a casa hoje paga 2,05.

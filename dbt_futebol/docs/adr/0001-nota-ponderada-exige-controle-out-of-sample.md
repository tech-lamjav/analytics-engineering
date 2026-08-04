---
status: accepted
---

# A nota ponderada exige controle out-of-sample

O Teste 2 só existe onde existe odd, então os pesos das premissas e o ROI que os
avalia saem **das mesmas ~168 partidas**. Ajustar e avaliar no mesmo dado produz curva
de ROI ascendente mesmo em dado aleatório — e o critério de aceite da Task [0.1] ("se
o ROI subir com a nota, a gente tem produto") aponta exatamente na direção que esse
viés fabrica. Decidimos, portanto, que **nenhuma conclusão de produto sai só do corte
in-sample**: o Teste 4 roda como especificado (pesos do Teste 2) acompanhado de dois
controles — pesos derivados do Teste 1, cujo universo de ~8.400 jogos encerrados é
disjunto do universo onde o ROI é medido, e um teste de permutação que mostra qual
curva o acaso produz em 168 jogos.

Pela mesma razão, o peso de uma premissa é `max(ganho, 0) × n/(n+k)` e não o ganho
cru. O achado central da Task [0] foi que **amostra curta fabrica sinal**: os +9,7%
vinham inteiramente de competições de mata-mata com 0,8 a 2,4 jogos disputados. Peso
proporcional ao ganho bruto daria as maiores notas justamente às premissas que
acenderam poucas vezes, reimportando o artefato pela porta dos pesos.

## Alternativas consideradas

- **Rodar o pedido literal e rotular como in-sample.** Rejeitada: a única leitura que
  sobreviveria seria um resultado plano, e "subiu" é o resultado que já foi
  pré-associado a "existe produto".
- **Tirar os pesos do Teste 1 e só dele.** Rejeitada: contraria a distinção correta do
  Victor Diody — o Teste 1 mede prever a linha, o Teste 2 mede bater o preço, e foi
  essa distinção que primeiro salvou e depois derrubou o `xg_combinado_alto`. Vira
  controle, não fonte.
- **Validação cruzada dentro das 168 partidas.** Rejeitada por poder: cada fold ficaria
  com ~34 jogos e a estimativa não distinguiria nada de nada.

## Consequências

Saem três curvas em vez de uma. Se as três concordarem, a conclusão é forte em
qualquer direção. Se só a in-sample subir, a conclusão é "não há produto detectável
nesta amostra" — e o gargalo passa a ser a task C2 (ampliar a coleta de odds), não a
calibragem de peso.

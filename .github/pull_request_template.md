<!--
Se este PR fecha uma issue do MESMO repo, a PRIMEIRA linha do corpo (antes de qualquer
outro texto) deve ser "Closes #<N>", bare — sem o prefixo DE#/AE# usado em conversa e sem
formatá-la como link markdown. É a ÚNICA sintaxe que o GitHub reconhece para fechar a
issue automaticamente ao mergear; "Closes AE#153" e "[AE#153](url)" NÃO fecham (já
aconteceu: PR #154 aqui, PR #99 no data-engineering).

Se a issue for de OUTRO repo, use o path completo: "Closes owner/repo#N".

Depois de mergear, confirme com `gh issue view N --json state` — se continuar OPEN, feche
à mão com `gh issue close N` e registre o link do PR num comentário.

Pode repetir a referência como link legível (ex. [AE#153](url)) no corpo do PR — isso não
substitui a linha "Closes #N" acima, só complementa.
-->

Closes #

## Por que a mudança

## Resumo da mudança

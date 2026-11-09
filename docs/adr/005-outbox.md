# ADR 005: integração por outbox

**Contexto.** O faturamento precisa avisar um serviço externo. Chamar a rede dentro da transação prenderia registros enquanto o serviço responde, e chamar depois do commit perderia o evento se o processo caísse no meio.

**Decisão.**
- O evento é gravado na **mesma transação** do faturamento, e um worker publica depois do commit, sem transação aberta durante a rede (`NoTransactionIsOpenDuringTheCall`).
- A entrega é **pelo menos uma vez**. A idempotency key é estável entre tentativas, e quem recebe deduplica. Por isso repetir é seguro mesmo quando a resposta se perde depois de o servidor aplicar.
- Retry imediato, com backoff e jitter, só para falha transitória (408, 425, 429, 5xx, queda de conexão) **e** operação segura (GET ou com chave). POST sem chave nunca é repetido: a falha é ambígua, e o servidor pode ter aplicado.
- Esgotado o retry imediato, o evento volta para a fila com backoff de 1 a 60 minutos. Depois de 8 tentativas, ou em 4xx permanente, vira `DEAD` e pode ser reenfileirado pela tela.
- Vários workers: `WITH LOCK SKIP LOCKED` e posse com validade (`claimed_until`). Worker que morre libera o evento quando a posse expira.
- Log de integração registra método, URL, status, duração e correlação. Cabeçalhos não entram, e o corpo passa por `RedactSecrets`.

**Consequências.** Exige Firebird 5, por causa do `SKIP LOCKED`. O serviço externo é simulado (`tools/mock_fiscal_api.py`), e a integração não foi testada contra nenhum serviço real. Não há garantia de ordem entre eventos.

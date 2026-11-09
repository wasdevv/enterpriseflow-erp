# ADR 002: isolamento e estratégia de bloqueio

**Contexto.** Dois vendedores podem confirmar pedidos para a última unidade ao mesmo tempo. Ler o saldo e depois gravar não é seguro: sem bloqueio, os testes mostraram atualizações perdidas (reservado `15` em vez de `30`).

**Decisão.**
- **Isolamento:** `READ COMMITTED`, `RECORD_VERSION`, `WAIT`, `LOCK TIMEOUT 5`. Quem espera lê o valor já confirmado depois de obter o bloqueio, que é o que faz a revalidação enxergar a venda do concorrente. `SNAPSHOT` falharia com conflito em vez de revalidar.
- **Bloqueio pessimista:** `SELECT ... WITH LOCK`, linha a linha.
- **Ordem global:** cliente, depois pedido, depois saldos em ordem crescente de produto e depósito. A ordem dos itens digitados não importa. Transferência bloqueia pelo id do depósito, não pela direção, para A→B e B→A não travarem.
- **Cliente primeiro:** sem isso, duas vendas de produtos diferentes para o mesmo cliente estourariam o limite de crédito juntas.
- **Última linha de defesa:** `CHECK` em saldo e parcela, triggers que tornam Kardex, auditoria e liquidações imutáveis, e `UNIQUE` para idempotência.
- **Conflito:** esgotado o tempo de espera, o usuário recebe "registro em uso, tente novamente", e nada fica gravado.

**Consequências.** Vendas do mesmo cliente são serializadas, o que é aceitável com 3 vendedores. A ordem é verificada em `BalancesAreLockedInAscendingOrderWhateverTheInputOrder`, porque o teste de estresse sozinho dependia de sorte de agendamento.

**Alternativa rejeitada.** `UPDATE ... WHERE on_hand - reserved >= :q`, sem bloqueio prévio. É mais simples para um item, mas não dá a mensagem de qual item faltou nem serve à validação conjunta antes de criar o pedido, como pede o fluxo da especificação.

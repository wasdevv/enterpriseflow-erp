# ADR 003: políticas de negócio

A especificação deixa estas escolhas em aberto ou as descreve de duas formas.

- **Baixa de estoque no faturamento.** A seção 4.3 admite expedição ou faturamento, e a seção 6 converte a reserva ao faturar. Adotado o faturamento: entre `SHIPPED` e `INVOICED` a mercadoria continua reservada.
- **Só `SHIPPED` fatura.** A seção 6 fala em pedido "separado", mas a máquina de estados da seção 8 passa por `SHIPPED`. Vale a máquina de estados.
- **Reserva é tudo ou nada.** Faltou um item, o pedido inteiro é recusado e a mensagem diz qual. Reserva parcial exigiria pedido pendente, que não está no escopo.
- **Atraso é derivado da data**, não um status gravado: `OVERDUE` nunca fica desatualizado, e não precisa de rotina noturna. A seção 8 permite as duas formas.
- **Estorno devolve o título ao estado anterior** (`PAID` para `PARTIALLY_PAID` ou `OPEN`). O diagrama não mostra essa volta, mas sem ela o estorno não teria efeito no saldo.
- **Preço vem do cadastro**, nunca de quem chama, e é fixado ao criar o pedido. Não há desconto por item.
- **Exposição de crédito** soma títulos em aberto e pedidos que já seguram estoque. Limite zero recusa a venda.
- **Ajuste de inventário** exige aprovação de outra pessoa, verificado no serviço e num `CHECK`. Contagem abaixo do reservado é recusada: primeiro cancele os pedidos.
- **Recebimento acima do pedido** é aceito, mas exige observação e aparece no relatório de divergências.
- **Número de fatura** vem de `SEQUENCE`: rollback pode deixar buraco na numeração. Serve a um documento interno; nota fiscal real exigiria numeração sem lacunas.

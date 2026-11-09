# Especificação original do EnterpriseFlow ERP

Texto de partida do projeto, mantido como referência. O que está de fato implementado e verificado fica no [README](../README.md).

ERP desktop de portfólio para uma distribuidora fictícia de materiais elétricos. O projeto demonstra desenvolvimento com Delphi VCL, Firebird, FireDAC, arquitetura em camadas, consistência transacional, concorrência, integrações REST e testes automatizados.

> **Transparência:** Distribuidora São Lucas e seus dados operacionais são fictícios. Este repositório é um projeto de portfólio, não uma implantação comercial. Só descreva como implementado aquilo que estiver efetivamente desenvolvido e testado.

## 1. Cenário de negócio

A Distribuidora São Lucas opera com 12 funcionários, 3 vendedores, 2 depósitos, aproximadamente 8.000 SKUs, 1.500 pedidos por mês e cerca de 400 movimentações de estoque por dia.

Problemas simulados:
- Divergências entre estoque físico e saldo registrado.
- Venda concorrente da última unidade por vendedores diferentes.
- Falta de rastreabilidade de alterações em pedidos e pagamentos.
- Conferência manual de contas a receber e pagamentos parciais.
- Dificuldade para identificar pedidos reservados, separados, faturados ou cancelados.

O sistema deve centralizar vendas, estoque e financeiro, preservando consistência dos dados mesmo diante de falhas e operações concorrentes.

## 2. Objetivos técnicos

- Aplicar regras de negócio fora dos formulários VCL.
- Garantir atomicidade entre pedido, baixa/reserva de estoque e geração de títulos.
- Impedir estoque negativo e reserva duplicada sob concorrência.
- Manter trilha de auditoria de operações sensíveis.
- Integrar com um serviço REST externo usando timeout, retry controlado e idempotência quando aplicável.
- Criar testes unitários e de integração para regras críticas.
- Medir consultas e operações demoradas antes de otimizá-las.

## 3. Stack

- Delphi / Object Pascal
- VCL para interface desktop
- Firebird SQL
- FireDAC para acesso a dados
- DUnitX para testes
- API REST via `TNetHTTPClient` ou cliente equivalente
- Git para versionamento

Docker pode ser usado para executar o Firebird em ambiente de desenvolvimento, conforme a versão escolhida. A aplicação VCL continua sendo executada no Windows.

## 4. Módulos funcionais

### 4.1 Cadastros
- Produtos, categorias, unidades de medida e códigos SKU.
- Clientes, fornecedores e transportadoras.
- Usuários, perfis e permissões.
- Depósitos e endereços de armazenamento.
- Histórico de alterações cadastrais relevantes.

### 4.2 Compras e recebimento
- Cadastro de pedido de compra.
- Recebimento parcial ou total.
- Conferência de quantidades recebidas.
- Entrada de estoque vinculada ao documento de origem.
- Registro de divergências entre quantidade pedida e recebida.

### 4.3 Estoque
- Saldo por produto e depósito.
- Reserva de estoque para pedidos confirmados.
- Baixa de estoque na expedição/faturamento, conforme política definida.
- Transferência entre depósitos.
- Ajuste de inventário com justificativa e aprovação.
- Kardex: histórico cronológico de entradas, saídas, reservas, liberações e ajustes.

### 4.4 Vendas
- Orçamento e pedido de venda.
- Validação de limite de crédito configurável.
- Reserva de itens disponíveis.
- Separação e expedição.
- Cancelamento com liberação de reservas.
- Histórico de status do pedido.

### 4.5 Financeiro
- Geração de contas a receber a partir de vendas faturadas.
- Parcelamento e vencimentos.
- Liquidação parcial e integral.
- Registro de juros, descontos e multas conforme regras configuradas.
- Estorno auditável.
- Relatório de títulos em aberto e vencidos.
- Fluxo de caixa previsto e realizado.

### 4.6 Integração
- Cliente REST para consultar ou transmitir dados a um serviço externo simulado.
- Timeout configurável e tratamento de falhas.
- Retry apenas para falhas transitórias e operações seguras para repetição.
- Registro de requisições, respostas e identificadores de correlação, sem armazenar segredos.
- Idempotency key para evitar duplicidade quando a API externa suportar esse mecanismo.

## 5. Fluxo crítico: confirmar pedido

1. Iniciar transação no Firebird.
2. Bloquear os registros de saldo relevantes, seguindo uma ordem determinística para reduzir deadlocks.
3. Revalidar disponibilidade de cada item dentro da transação.
4. Criar o pedido e seus itens.
5. Registrar as reservas de estoque.
6. Registrar evento de auditoria.
7. Confirmar a transação.
8. Se qualquer etapa falhar, executar rollback.

A aplicação não deve confiar apenas no saldo exibido anteriormente na tela: ele pode ter mudado enquanto o usuário revisava o pedido.

## 6. Fluxo crítico: faturar e gerar financeiro

1. Validar que o pedido está separado e apto ao faturamento.
2. Iniciar transação.
3. Bloquear o pedido e validar seu estado atual.
4. Converter reservas em baixas definitivas, conforme a política de estoque.
5. Criar o documento de faturamento interno.
6. Gerar títulos e parcelas a receber.
7. Registrar eventos de auditoria.
8. Confirmar a transação.

A integração com serviços externos não deve manter uma transação SQL aberta durante chamadas de rede. Para entregas confiáveis, considerar uma tabela de outbox e um worker que processe eventos após o commit.

## 7. Regras de negócio

- O saldo disponível é calculado considerando saldo físico e quantidade reservada.
- Uma confirmação de pedido não pode reservar quantidade superior à disponível.
- Cancelar um pedido reservado deve liberar a reserva uma única vez.
- Uma reserva liberada não pode ser liberada novamente.
- Um pedido faturado não pode voltar silenciosamente para o estado de orçamento.
- Pagamentos parciais não podem exceder o saldo em aberto.
- Estornos devem preservar a operação original e gerar registros compensatórios.
- Valores monetários devem usar tipos decimais e colunas `NUMERIC`/`DECIMAL`, nunca `Single` ou `Double` para cálculos financeiros.
- Alterações de estoque precisam registrar motivo, usuário, data e documento de origem.
- Operações repetidas precisam ser protegidas por restrições únicas, validação de estado e/ou chaves de idempotência.

## 8. Máquina de estados

### Pedido

```text
DRAFT -> CONFIRMED -> RESERVED -> PICKING -> SHIPPED -> INVOICED
   |          |           |
   +----------+-----------+----> CANCELLED
```

As transições devem ser validadas por um serviço de domínio. Não permitir alteração arbitrária de status diretamente na interface.

### Título financeiro

```text
OPEN -> PARTIALLY_PAID -> PAID
  |
  +-> OVERDUE
  |
  +-> CANCELLED
```

Atraso pode ser uma condição derivada da data de vencimento, em vez de um status persistido, dependendo da decisão de modelagem.

## 9. Modelo de dados inicial

| Tabela | Responsabilidade |
|---|---|
| `users` | Usuários |
| `roles` / `user_roles` | Perfis e permissões |
| `customers` | Clientes |
| `suppliers` | Fornecedores |
| `products` | Produtos |
| `warehouses` | Depósitos |
| `stock_balances` | Saldo atual por produto e depósito |
| `stock_movements` | Kardex e histórico de movimentações |
| `stock_reservations` | Reservas vinculadas a pedidos |
| `purchase_orders` / `purchase_order_items` | Compras |
| `sales_orders` / `sales_order_items` | Pedidos de venda |
| `invoices` | Faturamento interno |
| `receivable_titles` | Contas a receber |
| `receivable_installments` | Parcelas |
| `receivable_settlements` | Liquidações |
| `audit_events` | Auditoria |
| `outbox_events` | Eventos pendentes de publicação |
| `integration_logs` | Diagnóstico de integrações |

Criar índices a partir dos padrões reais de consulta, por exemplo produto + depósito para saldo e status + data para filas operacionais. Validar cada índice com planos de execução e medições; não adicionar índices indiscriminadamente.

## 10. Arquitetura sugerida

```text
src/
  presentation/
    forms/
    frames/
  application/
    services/
    usecases/
    dto/
  domain/
    entities/
    valueobjects/
    rules/
    exceptions/
  infrastructure/
    database/
    repositories/
    integrations/
    reporting/
  shared/
    logging/
    validation/

database/
  migrations/
  seeds/

tests/
  unit/
  integration/
  fixtures/
```

### Camadas

- **Presentation:** formulários VCL e interação com o usuário.
- **Application:** coordenação de casos de uso, como confirmar pedido e liquidar título.
- **Domain:** entidades, estados, invariantes e regras de negócio.
- **Infrastructure:** FireDAC, repositórios, integração HTTP, logs e relatórios.

Evitar SQL e regras financeiras diretamente nos eventos `OnClick` dos formulários.

## 11. Concorrência e integridade

Para confirmar pedidos concorrentes:
- Revalidar o saldo dentro da transação.
- Usar estratégia de locking compatível com a versão do Firebird.
- Aplicar restrições de integridade no banco.
- Atualizar saldo e inserir movimento na mesma transação.
- Tratar conflitos com mensagem clara para o usuário.
- Testar dois processos tentando reservar a última unidade.

Não assumir que uma consulta seguida de um `UPDATE` sem bloqueio seja segura. Documentar o nível de isolamento e a estratégia de locking adotada.

## 12. Testes automatizados

Com DUnitX e banco de integração isolado:

### Estoque
- Não permitir reserva acima do saldo disponível.
- Cancelar pedido libera reserva exatamente uma vez.
- Transferência debita um depósito e credita outro atomicamente.
- Dois usuários disputando a última unidade não geram saldo negativo.

### Vendas
- Não faturar pedido cancelado.
- Não confirmar pedido sem disponibilidade.
- Repetir confirmação não cria outro pedido nem outra reserva.

### Financeiro
- Liquidação parcial atualiza saldo corretamente.
- Impedir pagamento acima do saldo.
- Falha na gravação de movimento causa rollback do conjunto.
- Estorno mantém trilha histórica.

### Integração
- Timeout não deixa pedido em estado inconsistente.
- Retry não duplica operação externa quando há suporte a idempotência.
- Evento da outbox pode ser reprocessado sem duplicar efeito.

## 13. Observabilidade

- Logs estruturados com identificador de correlação.
- Duração de operações de banco e integração.
- Registro de falhas e retries.
- Métricas de pedidos confirmados, reservas recusadas e integrações com falha.
- Não registrar senhas, tokens, dados completos de cartão ou informações pessoais desnecessárias.

## 14. Roadmap de implementação

O estado de cada item está no [README](../README.md#roadmap).

## 15. Como executar

A documentação de execução deve ser completada quando a versão inicial estiver implementada. Incluir:
- Versão exata do Delphi.
- Versão do Firebird.
- Configuração de conexão FireDAC sem credenciais reais.
- Comando/script para criar e popular o banco.
- Passos para compilar e executar.
- Passos para rodar testes.
- Usuário e dados de demonstração não sensíveis.

## 16. História de negócio para apresentação

**Cenário fictício:** a Distribuidora São Lucas precisava evitar divergências de estoque e falhas na integração entre vendas e financeiro. Durante a operação, dois vendedores podiam confirmar pedidos simultaneamente para a última unidade disponível. Além disso, cancelamentos e falhas de integração dificultavam a reconciliação dos registros.

**Solução proposta:** desenvolver um ERP desktop em Delphi com Firebird, centralizando pedidos, reservas de estoque, faturamento e contas a receber. A confirmação do pedido valida a disponibilidade dentro de uma transação, registra reservas e movimentos auditáveis, enquanto uma outbox permite processar integrações após a confirmação no banco.

**Como contar isso honestamente:** apresente como estudo de caso simulado e explique as decisões técnicas. Não diga que foi contratado por essa empresa nem atribua ganhos operacionais reais. Depois de implementar, substitua hipóteses por medições reproduzíveis.

## 17. Exemplos de bullets para currículo após implementação

Use somente os bullets cujas funcionalidades você realmente concluiu e consegue demonstrar:

- Desenvolvi um ERP desktop em Delphi VCL e Firebird, estruturado em camadas, integrando pedidos de venda, controle de estoque, faturamento e contas a receber.
- Implementei reserva concorrente de estoque com transações e locking no Firebird, protegendo a disponibilidade de produtos contra vendas simultâneas.
- Desenvolvi fluxo transacional de faturamento que integra baixa de estoque e geração de títulos financeiros, com rollback para falhas e trilha de auditoria.
- Implementei integração REST com timeout, tratamento de falhas, retry controlado e processamento via outbox para evitar perda de eventos após o commit.
- Criei testes automatizados com DUnitX para regras financeiras, transições de pedidos, liquidação parcial e cenários de concorrência.

Não inventar percentuais de ganho, volume de produção ou resultados de cliente. Se houver benchmark, documentar ambiente, conjunto de dados, método e resultado antes/depois.

## Licença

Defina uma licença antes de publicar o repositório.

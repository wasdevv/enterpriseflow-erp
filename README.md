# EnterpriseFlow ERP

ERP desktop de portfólio para uma distribuidora fictícia de materiais elétricos: vendas, estoque, compras e financeiro, em Delphi VCL e Firebird, com foco em consistência sob concorrência e falha.

> **Transparência.** A Distribuidora São Lucas e seus dados são fictícios. Este é um projeto de portfólio, não uma implantação comercial.

> **Estado: ainda não compilado em Delphi.** Foi desenvolvido sem acesso a um compilador Delphi. Regras, SQL, concorrência e telas foram compilados e executados com Free Pascal e LCL, contra um Firebird real. Os adaptadores FireDAC e `TNetHTTPClient`, os `.dproj` e a aparência na VCL estão pendentes. O detalhe está em [docs/verificacao-delphi.md](docs/verificacao-delphi.md).

## O que está verificado

| Verificação | Resultado | Como repetir |
|---|---|---|
| Testes unitários e de integração em Firebird 5.0.4 | 150 passando | `scripts/test.sh` |
| Roteiro ponta a ponta nas telas, com a LCL em Xvfb | 52 verificações | `scripts/ui-smoke.sh` |
| Sabotagem: remover uma trava ou regra precisa quebrar um teste | 16 de 16 detectadas | `scripts/mutation-check.py` |
| Corrida real pela última unidade | 8 threads e 4 processos: um vence, os outros recebem recusa | `ThreadsRacing...`, `ProcessesRacing...` |
| Índices medidos antes de entrar no schema | 4 adotados, 2 rejeitados | [docs/performance.md](docs/performance.md) |

### O que esses testes pegaram

Nenhum destes aparecia em teste unitário:

- **Limite de crédito nunca aplicado.** No Firebird 4+, `SUM` de `NUMERIC(18,2)` é INT128, que o driver entregava como `NULL` e o código lia como zero. Agora valor ilegível gera erro ([ADR 004](docs/adr/004-dinheiro-e-valor-ilegivel.md)).
- **Administrador sem nenhuma permissão.** `UNION` de literais vira `CHAR`, e os códigos gravados vinham com espaços à direita. O banco ignora esses espaços ao comparar; o aplicativo, não.
- **Filtro opcional sem índice.** `(:p = '' OR status = :p)` deixava o índice sem uso.
- **Testes fracos.** Na primeira rodada, 3 sabotagens passaram despercebidas, como a falta de bloqueio do cliente. Os testes foram reforçados.
- **Falha intermitente rara.** Em 3 de cerca de 1.000 corridas sob carga, uma conexão falhava. A causa era o driver do Free Pascal ao conectar em paralelo: num teste só de conexões, sem a trava, 6 de 8 rodadas falharam, e com a trava nenhuma falhou.

## Módulos

- **Cadastros:** produtos, categorias, clientes, fornecedores, transportadoras, depósitos e endereços, usuários e perfis. CPF e CNPJ validados, e mudança de preço e de limite de crédito vai para a auditoria.
- **Compras:** pedido, recebimento parcial ou total, entrada vinculada ao documento, divergências.
- **Estoque:** saldo por produto e depósito, reserva, transferência atômica, ajuste com aprovação de outra pessoa, Kardex imutável, reconciliação de saldo com Kardex.
- **Vendas:** orçamento, confirmação com reserva, limite de crédito, separação, expedição, cancelamento, histórico de status.
- **Financeiro:** fatura interna, títulos e parcelas sem perda de centavo, liquidação parcial, juros, multa e desconto, estorno compensatório, títulos vencidos, fluxo de caixa de entradas.
- **Integração:** outbox com worker em segundo plano, retry só quando é seguro, idempotency key, log sem segredos. O serviço externo é simulado.
- **Observabilidade:** log JSON com correlação, duração das operações, métricas de pedidos confirmados, reservas recusadas e integrações com falha.
- **Relatórios:** em tela, com exportação CSV.

## Como funciona a confirmação de pedido

```text
transação READ COMMITTED + WAIT, com espera máxima de 5 s
  procura a idempotency key               -> repetição devolve o pedido já criado
  bloqueia o cliente                      -> serializa a análise de crédito
  procura a chave de novo                 -> quem esperou agora enxerga o concorrente
  bloqueia saldos em ordem de produto e depósito e revalida a disponibilidade
  confere o limite de crédito
  cria pedido e itens, reserva, grava Kardex, histórico e auditoria
commit (qualquer falha: rollback de tudo)
```

A recusa grava uma métrica em transação própria, para sobreviver ao rollback. Decisões e alternativas: [bloqueio](docs/adr/002-isolamento-e-bloqueio.md), [políticas de negócio](docs/adr/003-politicas-de-dominio.md), [outbox](docs/adr/005-outbox.md), [compilação dupla](docs/adr/001-verificacao-sem-delphi.md).

## Arquitetura

```text
src/
  presentation/    formulários e frames VCL (DFM). Sem SQL e sem regra de negócio
  application/     casos de uso e portas (interfaces de repositório)
  domain/          dinheiro, quantidade, máquina de estados, saldo, parcela, políticas
  infrastructure/  FireDAC ou SQLdb, repositórios, HTTP, relatórios, worker
  shared/          log, validação de documentos, hash de senha
database/          migrations com checksum e seeds de demonstração
tests/             unit, integration, ui (mesma API do DUnitX)
```

As dependências apontam para dentro: `domain` não conhece banco nem tela, e `application` só vê as interfaces de `EF.Application.Ports`.

## Como executar

**Versões:** Firebird 5.0 (exigido por `SKIP LOCKED` e índice parcial) e Delphi 12 como alvo, sem compilação até agora. Para verificar sem Delphi: Free Pascal 3.2.2 e Lazarus 3 ou 4.

### Banco e serviço simulado

```bash
docker compose up -d    # Firebird na porta 3050 e serviço fiscal simulado na 8765
```

Copie `config/enterpriseflow.ini.example` para `config/enterpriseflow.ini` e preencha, ou use as variáveis `EF_DB_*`. Com o Docker, o caminho do banco é `/var/lib/firebird/data/enterpriseflow.fdb`.

```bash
efmigrate create
efmigrate migrate
efmigrate seed database/seeds/001_demo.sql
```

**Usuários de demonstração**, todos com a senha `demo1234`: `admin`, `vendedor1`, `vendedor2`, `vendedor3`, `estoque`, `financeiro` e `gerente`.

### Em Delphi (Windows)

Abra `EnterpriseFlow.dproj`, compile e execute. Na primeira vez, siga [docs/verificacao-delphi.md](docs/verificacao-delphi.md), porque ajustes são esperados.

### Sem Delphi (Linux)

```bash
sudo apt install fpc lcl lcl-gtk2 libgtk2.0-dev xvfb
./scripts/setup-firebird.sh          # Firebird 5 no diretório do usuário, porta 53050
export LD_LIBRARY_PATH=$HOME/.local/firebird-5/opt/firebird/lib:$LD_LIBRARY_PATH
./scripts/test.sh                    # testes unitários e de integração
./scripts/ui-smoke.sh ./capturas     # roteiro nas telas, com capturas opcionais
./scripts/mutation-check.py          # confere que os testes detectam sabotagem
```

## Limitações

- Sem compilação em Delphi, como descrito acima.
- Contas a pagar estão fora do escopo: o fluxo de caixa só tem entradas.
- Relatórios são em tela e CSV, sem layout de impressão.
- O serviço externo é simulado, e a fatura é interna, sem nota fiscal.
- Edição de cadastro não detecta alteração simultânea: vence o último a salvar, com o histórico na auditoria.
- Demonstração em vídeo não foi gravada.
- Sem licença definida: por isso o repositório é privado.

## Roadmap

- [x] Estrutura de pastas e projeto VCL (`.dproj` ainda não aberto no IDE)
- [x] Firebird e adaptadores de acesso (FireDAC ainda não compilado)
- [x] Migrations e dados de demonstração
- [x] Autenticação, permissões e bloqueio por tentativas
- [x] Cadastros
- [x] Saldo, movimentos e Kardex
- [x] Reserva concorrente de estoque
- [x] Pedido de venda e cancelamento
- [x] Faturamento e contas a receber
- [x] Auditoria e outbox
- [x] Integração REST simulada (`TNetHTTPClient` ainda não compilado)
- [x] Relatórios operacionais e financeiros
- [x] Testes unitários e de integração (com shim; DUnitX real pendente)
- [ ] Compilar e validar em Delphi
- [ ] Gravar demonstração

A especificação completa está em [docs/especificacao.md](docs/especificacao.md).

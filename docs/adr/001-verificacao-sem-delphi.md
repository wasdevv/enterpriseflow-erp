# ADR 001: compilar o mesmo código em Delphi e Free Pascal

**Contexto.** O produto é Delphi VCL, mas não há licença de Delphi na máquina de desenvolvimento nem em CI. Sem compilador, regra de negócio e SQL ficariam sem nenhuma verificação.

**Decisão.** Domínio, aplicação, repositórios, telas e testes compilam nos dois compiladores. O que é exclusivo de cada um fica atrás de uma interface pequena: `IDbSession` (FireDAC ou SQLdb) e `IHttpTransport` (`TNetHTTPClient` ou `fphttpclient`). A SQL é a mesma, e o leitor de resultado é compartilhado, porque `TFDQuery` e `TSQLQuery` são ambos `TDataSet`. As telas usam nomes de unidade sem prefixo, que o Delphi resolve pelo `DCC_Namespace` e a LCL resolve direto.

**Consequências.**
- Dá para rodar regra, SQL, concorrência e telas de verdade em CI, e gerar `.exe` nativo de Windows a partir do WSL.
- O código abre mão de recursos que o FPC 3.2.2 não tem: métodos anônimos, atributos e variáveis inline.
- Os dois adaptadores Delphi e os `.dproj` seguem sem compilar, até alguém abrir o projeto no Delphi. A superfície é pequena e está listada em [verificacao-delphi.md](../verificacao-delphi.md), mas não é zero: **nada aqui permite dizer que o projeto roda em Delphi**.

**Alternativa rejeitada.** Escrever só para Delphi, sem compilar: o texto ficaria mais idiomático, e nenhum dos bugs encontrados pelos testes teria aparecido.

# O que foi verificado, e como

Este projeto foi escrito numa máquina sem Delphi. Este documento separa o que foi executado do que só foi escrito.

## Estado

| Parte | Verificação | Delphi |
|---|---|---|
| Domínio, serviços, repositórios e SQL | Compilados com Free Pascal 3.2.2 e executados em Linux e **como `.exe` nativo no Windows**, com o `fbclient.dll` oficial, contra Firebird 5.0.4 real | Não compilado |
| Corrida entre processos reais | `race_worker.exe` no Windows, pelo Free Pascal | Ramo `CreateProcess` conferido só em tipos |
| Migrations, travas, índices e constraints | Executados no Firebird 5.0.4 | Não dependem de Delphi |
| Formulários, frames e DFMs | Compilados com a LCL 4.4 e dirigidos em **controles nativos Win32**, por `tests/ui/UiSmoke.lpr` e `BootSmoke.lpr` | Não abertos na VCL |
| `EF.Infrastructure.Database.FireDAC.pas` | Sintaxe e tipos conferidos contra uma simulação da API | **Nunca compilado de verdade** |
| `EF.Infrastructure.Http.Net.pas` | Sintaxe e tipos conferidos contra uma simulação da API | **Nunca compilado de verdade** |
| `EnterpriseFlow.dpr` | Compilado com Free Pascal, trocando `Vcl.Forms` por `Forms` | **Nunca compilado de verdade** |
| Os `.dproj` | XML, caminhos e referências conferidos | **Nunca abertos no IDE** |
| Testes com o DUnitX de verdade | Rodam com um shim mínimo (`tests/fpc-shim`), com a mesma API | Pendente |

A LCL imita a VCL, mas não é a VCL. Usa os mesmos controles nativos do Windows, então layout e comportamento devem ficar próximos, porém isso não prova que o projeto compila nem roda em Delphi.

## Verificações sem Delphi

| Comando | O que prova | O que não prova |
|---|---|---|
| `scripts/test-windows.sh` | Regras, SQL, concorrência, processos e rede em Windows real | Nada sobre FireDAC ou o compilador Delphi |
| `scripts/ui-smoke-windows.sh` | Telas e fluxos em controles Win32, numa área de trabalho oculta | Aparência e comportamento da VCL |
| `scripts/check-delphi-rules.py` | Regras que o Free Pascal não cobra: literal acima de 255 caracteres, `[]` em array aberto, identificadores só de FPC, `Exit` em `finally`, DFM coerente com a classe, propriedades conhecidas da VCL, caminhos dos projetos | Só as classes de erro listadas |
| `scripts/typecheck-delphi-paths.py` | Sintaxe e tipos dos ramos de Delphi (`-uFPC`) contra `tools/delphi-typecheck` | A API real: as simulações saíram da documentação e podem estar erradas |

Estas duas últimas foram testadas com 11 erros injetados de propósito, e todos foram acusados.

## Compilar em Delphi

Só isto falta para fechar o projeto. Exige uma pessoa, porque a licença é pessoal:

1. Peça a [licença gratuita da edição Community](https://www.embarcadero.com/products/delphi/starter/free-download). Ela é [limitada a receita abaixo de US$ 5.000 por ano e vale por um ano](https://www.embarcadero.com/products/delphi/starter/faq). A chave chega por e-mail, e a versão atual é a 13.0 Florence.
2. Instale pelo instalador web. Na tela de licença, escolha **I already have a product serial number** e cole a chave do e-mail. Marque Delphi e a plataforma Windows.
3. Instale um `fbclient.dll` 5.x da mesma arquitetura do executável.
4. Compile:
   - **Com compilador de linha de comando:** `scripts/build-delphi.sh` (no WSL) ou `scripts\windows\build-delphi.ps1`. Ele acha a instalação e compila os quatro projetos.
   - **Sem ele:** o [FAQ](https://www.embarcadero.com/products/delphi/starter/faq) só diz que mover o compilador para outra máquina é vantagem das edições pagas, e [um comentário no blog da Embarcadero](https://blogs.embarcadero.com/delphi-11-and-cbuilder-11-community-editions-released) diz que a Community não o traz. Nesse caso o script avisa, e a compilação é pelo IDE: abra cada `.dproj` e use Project > Build.
5. Rode `tests/EnterpriseFlowTests` com `EF_TEST_DB_*` e `EF_TEST_API_URL`. Sem `tests\fpc-shim` no search path, os testes usam o DUnitX real.
6. Rode `EnterpriseFlow` e percorra o roteiro de `tests/ui/UiSmoke.lpr` à mão.
7. Só então atualize a tabela acima e use os bullets da especificação.

## Limite da edição gratuita

O [FAQ](https://www.embarcadero.com/products/delphi/starter/faq) diz que a Community inclui conectividade local e embarcada, e que acesso remoto cliente/servidor exige Enterprise ou Architect. A [página do FireDAC](https://www.embarcadero.com/products/firedac-faq) cita "Firebird Embedded, and Firebird on localhost" na faixa local. Portanto, este projeto deve funcionar com o Firebird em `localhost`, inclusive em Docker ou WSL com porta local, e o cenário de vários computadores acessando um servidor exigiria edição paga. Confirme na primeira execução: não houve como testar aqui.

## Onde esperar correção

Escrito contra a documentação, sem compilador para confirmar:

- **`lock_timeout` no FireDAC.** A documentação de [`TFDTxOptions.Params`](https://docwiki.embarcadero.com/Libraries/Athens/en/FireDAC.Stan.Option.TFDTxOptions.Params) não detalha este parâmetro. Uma [resposta na lista firebird-support](https://fb-list-archive.lawinegevaar.nl/firebird-support/2019/4/133922.html) diz que o FireDAC aceita os dois nomes, com valor inteiro. O [exemplo oficial](https://docwiki.embarcadero.com/RADStudio/Athens/en/Managing_Transactions_(FireDAC)) mostra `read_committed`, `rec_version` e `nowait`. Confirme com os testes de corrida: o conflito tem de esperar, não falhar na hora.
- **`DisplayText` com tipos do FireDAC.** A distinção entre dinheiro e quantidade usa `TField.Size` (escala). O FireDAC pode mapear `NUMERIC` para `TBCDField` ou `TFMTBCDField`; os dois casos estão tratados, mas só um foi executado.
- **Unidades sem prefixo de namespace** (`Forms`, `DB`, `SysUtils`), para o mesmo fonte compilar nos dois compiladores. Dependem do `DCC_Namespace` que está no `.dproj`.
- **Versão do projeto.** Os `.dproj` foram marcados como Delphi 12 (`ProjectVersion` 20.1). O IDE converte para a versão instalada; se recusar, abra o `.dpr` e deixe o IDE gerar outro.
- **`TNetHTTPClient`:** timeout e exceções de rede, que só os testes em Delphi confirmam.

## Armadilhas já tratadas

Revisão feita porque o Free Pascal aceita e o Delphi não:

- `case` sobre `Int64` não compila em Delphi: `ClassifyFirebirdError` recebe `Integer`.
- Concatenar `RawByteString` de codepages diferentes converte os bytes em Delphi: o hash de senha trabalha só com `TBytes`.
- Fonte sem BOM é lido como ANSI: `scripts/normalize-sources.py --check` barra isso no CI.
- `[]` como argumento pode ser lido como conjunto vazio: os testes têm sobrecarga sem parâmetros.
- Atributos e métodos anônimos não existem no FPC 3.2.2: os testes usam métodos `published`, que o DUnitX [reconhece como teste](https://github.com/VSoftTechnologies/DUnitX/blob/master/Source/DUnitX.FixtureProvider.pas) sem atributo.
- `FixedRows` precisa ser menor que `RowCount` na VCL: `FillGrid` mantém uma linha em branco.

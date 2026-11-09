# O que foi verificado, e como

Este projeto foi escrito numa máquina sem Delphi. Este documento separa o que foi executado do que só foi escrito.

## Estado

| Parte | Verificação | Delphi |
|---|---|---|
| Domínio, serviços, repositórios e SQL | Compilados com Free Pascal 3.2.2 e executados contra Firebird 5.0.4 real | Não compilado |
| Migrations, travas, índices e constraints | Executados no Firebird 5.0.4 | Não dependem de Delphi |
| Formulários, frames e DFMs | Compilados com a LCL 4.4 e dirigidos em Xvfb (GTK2) por `tests/ui/UiSmoke.lpr` | Não compilado nem aberto na VCL |
| `EF.Infrastructure.Database.FireDAC.pas` | **Nunca compilado** | Pendente |
| `EF.Infrastructure.Http.Net.pas` | **Nunca compilado** | Pendente |
| `EnterpriseFlow.dpr` e os `.dproj` | **Nunca abertos no IDE**, escritos à mão | Pendente |
| Testes com o DUnitX de verdade | Rodam com um shim mínimo (`tests/fpc-shim`), com a mesma API | Pendente |
| Ramo Windows de `EF.Tests.Spawn.pas` | **Nunca compilado** | Pendente |

A LCL imita a VCL, mas não é a VCL: passar aqui prova nomes, eventos, fluxo e dados, não a aparência nem o comportamento no Windows.

## Primeira compilação em Delphi

1. Instale o Delphi e um `fbclient.dll` 5.x da mesma arquitetura do executável.
2. Confirme se a sua edição conecta no Firebird. As edições têm limites de conectividade no FireDAC, e a [Community costuma ser limitada a banco local](https://kiwix.lema.org/stackoverflow.com_en_all_2023-11/questions/65722383/connect-firedac-to-sql-server-database). A [página do FireDAC](https://www.embarcadero.com/application-development/firedac-data-access-components) cita Firebird em localhost e embarcado, mas não diz por edição. Confira a matriz de recursos da sua versão e teste a conexão.
3. Abra `EnterpriseFlow.dproj`. Os projetos foram marcados como Delphi 12 (`ProjectVersion` 20.1); o IDE converte se precisar. Se ele recusar o arquivo, abra o `.dpr` e deixe o IDE gerar outro.
4. Rode `tools/efmigrate.dproj` e crie o banco, como no README.
5. Compile `tests/integration/race_worker.dproj` e `tests/EnterpriseFlowTests.dproj`, que saem na mesma pasta, e rode os testes com `EF_TEST_DB_*` e `EF_TEST_API_URL`. Sem `tests\fpc-shim` no search path, eles usam o DUnitX real.
6. Rode `EnterpriseFlow` e percorra o roteiro de `tests/ui/UiSmoke.lpr` à mão.
7. Só então atualize a tabela acima e use os bullets da especificação.

## Onde esperar correção

Escrito contra a documentação, sem compilador para confirmar:

- **`lock_timeout` no FireDAC.** A documentação de [`TFDTxOptions.Params`](https://docwiki.embarcadero.com/Libraries/Athens/en/FireDAC.Stan.Option.TFDTxOptions.Params) não detalha este parâmetro. Uma [resposta na lista firebird-support](https://fb-list-archive.lawinegevaar.nl/firebird-support/2019/4/133922.html) diz que o FireDAC aceita os dois nomes, com valor inteiro. O [exemplo oficial](https://docwiki.embarcadero.com/RADStudio/Athens/en/Managing_Transactions_(FireDAC)) mostra `read_committed`, `rec_version` e `nowait`. Confirme com os testes de corrida: o conflito tem de esperar, não falhar na hora.
- **`DisplayText` com tipos do FireDAC.** A distinção entre dinheiro e quantidade usa `TField.Size` (escala). O FireDAC pode mapear `NUMERIC` para `TBCDField` ou `TFMTBCDField`; os dois casos estão tratados, mas só um foi executado.
- **Unidades sem prefixo de namespace** (`Forms`, `DB`, `SysUtils`), para o mesmo fonte compilar nos dois compiladores. Dependem do `DCC_Namespace` que está no `.dproj`.
- **`TNetHTTPClient`:** timeout e exceções de rede, que só os testes de integração em Windows confirmam.

## Armadilhas já tratadas

Revisão feita à mão, porque o Free Pascal aceita e o Delphi não:

- `case` sobre `Int64` não compila em Delphi: `ClassifyFirebirdError` recebe `Integer`.
- Concatenar `RawByteString` de codepages diferentes converte os bytes em Delphi: o hash de senha trabalha só com `TBytes`.
- Fonte sem BOM é lido como ANSI: `scripts/normalize-sources.py --check` barra isso no CI.
- Atributos e métodos anônimos não existem no FPC 3.2.2: os testes usam métodos `published`, que o DUnitX [reconhece como teste](https://github.com/VSoftTechnologies/DUnitX/blob/master/Source/DUnitX.FixtureProvider.pas) sem atributo.
- `FixedRows` precisa ser menor que `RowCount` na VCL: `FillGrid` mantém uma linha em branco.

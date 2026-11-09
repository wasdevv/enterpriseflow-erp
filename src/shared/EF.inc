{ Compila em Delphi e em Free Pascal. O alvo do produto e Delphi VCL; o FPC verifica
  dominio, aplicacao, SQL e testes em CI, onde nao ha licenca de Delphi. }
{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
  {$WARN 5024 OFF}
  {$WARN 5023 OFF}
  {$WARN 4104 OFF}
  {$WARN 4105 OFF}
  {$WARN 5093 OFF}
{$ENDIF}

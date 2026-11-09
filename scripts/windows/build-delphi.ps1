# Compila os quatro projetos com o Delphi instalado nesta maquina e, com -RunTests, roda a suite.
# Uso: powershell -ExecutionPolicy Bypass -File scripts\windows\build-delphi.ps1 [-Platform Win64] [-RunTests]
param(
  [string]$Platform = "Win64",
  [string]$Config = "Debug",
  [switch]$RunTests
)
$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")

$Keys = @("HKCU:\Software\Embarcadero\BDS", "HKLM:\SOFTWARE\WOW6432Node\Embarcadero\BDS", "HKLM:\SOFTWARE\Embarcadero\BDS")
$Install = $null
foreach ($Key in $Keys) {
  if (Test-Path $Key) {
    $Latest = Get-ChildItem $Key | Sort-Object { [double]$_.PSChildName } | Select-Object -Last 1
    if ($Latest) { $Install = (Get-ItemProperty $Latest.PSPath).RootDir; if ($Install) { break } }
  }
}
if (-not $Install) {
  Write-Output "DELPHI_NAO_ENCONTRADO: nenhuma instalacao de RAD Studio ou Delphi no registro do Windows."
  exit 3
}
$Install = $Install.TrimEnd("\")
Write-Output "Delphi em: $Install"

$Rsvars = Join-Path $Install "bin\rsvars.bat"
$Compiler = if ($Platform -eq "Win64") { "dcc64.exe" } else { "dcc32.exe" }
if (-not (Test-Path (Join-Path $Install "bin\$Compiler"))) {
  # A edicao Community pode nao trazer compilador de linha de comando.
  Write-Output "SEM_LINHA_DE_COMANDO: $Compiler nao existe nesta edicao. Compile pelo IDE: abra os .dproj e use Project > Build."
  exit 4
}

$Projects = @("tools\efmigrate.dproj", "tests\integration\race_worker.dproj", "tests\EnterpriseFlowTests.dproj", "EnterpriseFlow.dproj")
$Failed = @()
foreach ($Project in $Projects) {
  Write-Output "=== $Project ($Platform $Config)"
  $Path = Join-Path $Root $Project
  $Command = "call `"$Rsvars`" && msbuild `"$Path`" /t:Build /nologo /v:minimal /p:Config=$Config /p:Platform=$Platform"
  cmd /c $Command
  if ($LASTEXITCODE -ne 0) { $Failed += $Project }
}
if ($Failed.Count -gt 0) {
  Write-Output "FALHOU: $($Failed -join ', ')"
  exit 1
}
Write-Output "COMPILOU: $($Projects.Count) projetos"

if ($RunTests) {
  $Output = Join-Path $Root "build\$Platform\$Config"
  & (Join-Path $Output "EnterpriseFlowTests.exe")
  exit $LASTEXITCODE
}

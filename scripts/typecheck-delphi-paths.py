#!/usr/bin/env python3
"""Compila com Free Pascal os ramos que so o Delphi usaria: {$IFNDEF FPC}, adaptador FireDAC,
TNetHTTPClient e EnterpriseFlow.dpr. O simbolo FPC e removido com -uFPC, e as APIs de Delphi
sao simuladas em tools/delphi-typecheck.

Pega erro de sintaxe, de tipo e de nome no NOSSO codigo. NAO confere a API real da Embarcadero:
as simulacoes foram escritas a partir da documentacao e podem estar erradas tambem.
"""
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FLAGS_SCRIPT = "source scripts/fpc-win64-env.sh; printf '%s\\n' \"$FPC_BIN\" \"$FPCRES_DIR\" \"$WIN_UNITS\" \"$WIN_BUILD\""
values = subprocess.run(["bash", "-c", FLAGS_SCRIPT], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split("\n")
FPC, FPCRES, WIN_UNITS, WIN_BUILD = values[:4]

work = pathlib.Path(tempfile.mkdtemp(prefix="ef-typecheck-"))
copy = work / "src"
output = work / "out"
output.mkdir()
for folder in ("src", "tests", "tools"):
    shutil.copytree(ROOT / folder, copy / folder, ignore=shutil.ignore_patterns("fpc-shim", "ui", "fpc"))
shutil.copy(ROOT / "EnterpriseFlow.dpr", copy)

RENAMES = {"System.SysUtils": "SysUtils", "System.Classes": "Classes", "Data.DB": "DB", "Winapi.Windows": "Windows",
           "Vcl.Forms": "Forms", "System.IOUtils": "IOUtilsStub"}
for path in copy.rglob("*"):
    if path.suffix not in {".pas", ".dpr"} or "delphi-typecheck" in path.parts:
        continue
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    for old, new in RENAMES.items():
        text = text.replace(old, new)
    if "FireDAC.Comp.Client" in text:
        text = re.sub(r"\n\s*FireDAC\.[^;]*?FireDAC\.Comp\.Client,", "\n  FireDACStub,", text, flags=re.S)
    if "System.Net." in text:
        text = re.sub(r"System\.Net\.URLClient,\s*System\.Net\.HttpClient,\s*System\.Net\.HttpClientComponent,", "NetStub,", text)
    if path.suffix == ".dpr":
        text = re.sub(r"in '([^']+)'", lambda m: "in '" + m.group(1).replace("\\", "/") + "'", text)
    path.write_text("﻿" + text, encoding="utf-8")

src_paths = [f"-Fu{d}" for d in {p.parent for p in copy.rglob("*.pas")}]
base = [FPC, "-n", "-Twin64", "-Px86_64", "-Mdelphi", "-Sh", "-uFPC", "-l-", "-vew", f"-FD{FPCRES}", f"-Fi{copy}/src/shared",
        f"-Fu{WIN_UNITS}/*", f"-FU{output}", f"-FE{output}", *src_paths]
lcl = [f"-Fu{WIN_BUILD}/lcl", "-FaInterfaces", "-dLCL", "-dLCLwin32"]

targets = [(copy / "tools/efmigrate.dpr", []), (copy / "tests/integration/race_worker.dpr", []),
           (copy / "tests/EnterpriseFlowTests.dpr", []), (copy / "EnterpriseFlow.dpr", lcl)]
if not os.path.isdir(f"{WIN_BUILD}/lcl"):
    print("Aviso: LCL de Windows ainda nao compilada (scripts/build-win64-lcl.sh): EnterpriseFlow.dpr fica de fora.")
    targets = targets[:-1]

failed = False
for program, extra in targets:
    done = subprocess.run(base + extra + [str(program)], capture_output=True, text=True, cwd=program.parent)
    lines = [l for l in done.stdout.splitlines() if re.search(r"\b(Error|Fatal)\b", l)]
    status = "ok" if done.returncode == 0 else "FALHOU"
    print(f"  {status}  {program.name}")
    for line in lines[:25]:
        print("     ", line.replace(str(copy) + "/", ""))
    failed = failed or done.returncode != 0
shutil.rmtree(work, ignore_errors=True)
sys.exit(1 if failed else 0)

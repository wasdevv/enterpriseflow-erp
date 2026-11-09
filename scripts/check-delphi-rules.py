#!/usr/bin/env python3
"""Confere o que o Free Pascal aceita e o Delphi recusa, e a coerencia dos projetos Delphi.

Roda sem Delphi. Nao substitui compilar: pega so as classes de erro listadas aqui.
"""
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
errors = []

# Fontes que so o Free Pascal compila: as regras de Delphi nao se aplicam a eles.
FPC_ONLY = ("tests/fpc-shim/", "tests/ui/", "tools/fpc/", "tools/delphi-typecheck/", "EF.Infrastructure.Database.SqlDb.pas", "EF.Infrastructure.Http.Fcl.pas")
FPC_ONLY_IDENTIFIERS = ("QWord", "PtrInt", "PtrUInt", "SizeInt", "SizeUInt", "GetTempDir", "specialize", "LazUTF8", "fphttpclient", "sqldb", "IBConnection")
MAX_LITERAL = 255  # E2056 em Delphi
MAX_LINE = 1023


def relative(path):
    return path.relative_to(ROOT).as_posix()


def is_fpc_only(path):
    text = relative(path)
    return any(marker in text for marker in FPC_ONLY)


def read(path):
    return path.read_text(encoding="utf-8-sig", errors="replace").replace("\r\n", "\n")


def strip_fpc_blocks(text):
    """Remove {$IFDEF FPC} ... {$ELSE|$ENDIF} e o ramo {$IFNDEF FPC} ... {$ELSE} ... {$ENDIF}."""
    output, stack = [], []
    for token in re.split(r"(\{\$(?:IFDEF|IFNDEF|IFOPT|ELSE|ENDIF)[^}]*\})", text):
        directive = re.match(r"\{\$(IFDEF|IFNDEF|IFOPT|ELSE|ENDIF)\s*([^}]*)\}", token)
        if directive:
            kind, name = directive.group(1), directive.group(2).strip()
            if kind in ("IFDEF", "IFNDEF", "IFOPT"):
                # Em Delphi, FPC nao esta definido.
                active = not (kind == "IFDEF" and name == "FPC")
                stack.append(active)
            elif kind == "ELSE" and stack:
                stack[-1] = not stack[-1]
            elif kind == "ENDIF" and stack:
                stack.pop()
            continue
        if all(stack):
            output.append(token)
    return "".join(output)


def strip_comments_and_literals(text, on_literal=None):
    """Devolve o codigo sem comentarios e com strings vazias; chama on_literal para cada string."""
    output, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "{":
            end = text.find("}", i)
            i = n if end < 0 else end + 1
        elif text.startswith("(*", i):
            end = text.find("*)", i)
            i = n if end < 0 else end + 2
        elif text.startswith("//", i):
            end = text.find("\n", i)
            i = n if end < 0 else end
        elif c == "'":
            j, size = i + 1, 0
            while j < n:
                if text[j] == "'":
                    if j + 1 < n and text[j + 1] == "'":
                        j += 2
                        size += 1
                        continue
                    break
                j += 1
                size += 1
            if on_literal:
                on_literal(size, text.count("\n", 0, i) + 1)
            output.append("''")
            i = j + 1
        else:
            output.append(c)
            i += 1
    return "".join(output)


sources = [p for p in ROOT.rglob("*") if p.suffix in {".pas", ".dpr"} and "build" not in p.parts and not is_fpc_only(p)]
for path in sources:
    raw = read(path)
    for number, line in enumerate(raw.split("\n"), 1):
        if len(line) > MAX_LINE:
            errors.append(f"{relative(path)}:{number}: linha com {len(line)} caracteres (limite do Delphi: {MAX_LINE})")
    text = strip_fpc_blocks(raw)

    def literal(size, number, path=path):
        if size > MAX_LITERAL:
            errors.append(f"{relative(path)}:~{number}: string literal com {size} caracteres (E2056: limite {MAX_LITERAL})")

    code = strip_comments_and_literals(text, literal)
    if re.search(r"\[\s*\]\s*\)", code):
        for match in re.finditer(r"[\w.]+\([^()\n]*\[\s*\]\s*\)", code):
            if "in [" not in match.group(0):
                errors.append(f"{relative(path)}: array vazio passado como argumento, recusado em array aberto tipado: {match.group(0)[:70]}")
    for word in FPC_ONLY_IDENTIFIERS:
        if re.search(rf"\b{word}\b", code, re.I):
            errors.append(f"{relative(path)}: identificador só de Free Pascal fora de IFDEF: {word}")
    if re.search(r"(\+=|-=|\*=)", code):
        errors.append(f"{relative(path)}: operador no estilo C não existe em Delphi")
    if re.search(r"\bcase\s+\w*(Int64|Id)\b", code):
        errors.append(f"{relative(path)}: conferir case sobre valor de 64 bits")
    # EXIT, BREAK e CONTINUE dentro de finally nao compilam em Delphi (E2126).
    for match in re.finditer(r"\bfinally\b(.*?)\bend\s*;", code, re.S | re.I):
        if re.search(r"\b(exit|break|continue)\b", match.group(1), re.I):
            errors.append(f"{relative(path)}: Exit/Break/Continue dentro de finally")

# Propriedades que existem na VCL, por classe. O que nao esta aqui precisa ser conferido a mao.
COMMON = {"Left", "Top", "Width", "Height", "Align", "Anchors", "Visible", "Enabled"}
VCL_PROPERTIES = {
    "TForm": COMMON | {"Caption", "BorderStyle", "ClientHeight", "ClientWidth", "Position", "Menu", "OnDestroy", "OnCreate", "OnShow"},
    "TFrame": COMMON | {"TabOrder"},
    "TPanel": COMMON | {"BevelOuter", "Caption", "TabOrder"},
    "TButton": COMMON | {"Caption", "TabOrder", "OnClick", "Default", "Cancel", "ModalResult"},
    "TEdit": COMMON | {"TabOrder", "Text", "PasswordChar", "OnChange"},
    "TLabel": COMMON | {"Caption", "ParentFont", "Font.Style", "Font.Height", "Font.Color"},
    "TComboBox": COMMON | {"Style", "TabOrder", "OnChange"},
    "TStringGrid": COMMON | {"ColCount", "DefaultRowHeight", "FixedCols", "RowCount", "FixedRows", "Options", "TabOrder", "OnClick"},
    "TPageControl": COMMON | {"ActivePage", "TabOrder", "OnChange"},
    "TTabSheet": {"Caption", "TabVisible"},
    "TSplitter": COMMON | {"Cursor"},
    "TCheckBox": COMMON | {"Caption", "TabOrder", "OnClick", "Checked"},
    "TStatusBar": COMMON | {"SimplePanel"},
    "TMainMenu": {"Left", "Top"},
    "TMenuItem": {"Caption", "OnClick"},
    "TSaveDialog": {"Left", "Top", "DefaultExt", "Filter"},
}
ROOT_BASE = {"Frame": "TFrame", "Form": "TForm"}

for dfm in (ROOT / "src").rglob("*.dfm"):
    pas = dfm.with_suffix(".pas")
    if not pas.exists():
        errors.append(f"{relative(dfm)}: sem .pas correspondente")
        continue
    objects, events, stack = {}, set(), []
    root_class = None
    for line in read(dfm).split("\n"):
        stripped = line.strip()
        match = re.match(r"object (\w+): (\w+)$", stripped)
        if match:
            stack.append(match.group(2))
            if root_class is None:
                root_class = match.group(2)
            else:
                objects[match.group(1)] = match.group(2)
            continue
        if stripped == "end":
            stack.pop()
            continue
        prop = re.match(r"([\w.]+) = (.*)$", stripped)
        if not prop:
            continue
        name, value = prop.groups()
        klass = stack[-1]
        if klass == root_class:
            klass = "TFrame" if "/frames/" in relative(dfm) else "TForm"
        allowed = VCL_PROPERTIES.get(klass)
        if allowed is None:
            errors.append(f"{relative(dfm)}: classe sem lista de propriedades VCL: {klass}")
        elif name not in allowed:
            errors.append(f"{relative(dfm)}: {klass}.{name} não está na lista de propriedades da VCL")
        if name.startswith("On"):
            events.add(value)
    code = strip_comments_and_literals(read(pas))
    declaration = re.search(rf"\b{root_class}\s*=\s*class\((\w+)\)(.*?)(?:\n\s*(?:private|protected|public)\b|\n\s*end\s*;)", code, re.S)
    if not declaration:
        errors.append(f"{relative(pas)}: classe {root_class} não encontrada")
        continue
    published = declaration.group(2)
    fields = {name: klass for name, klass in re.findall(r"^\s*(\w+)\s*:\s*(\w+)\s*;", published, re.M)}
    methods = set(re.findall(r"procedure\s+(\w+)\s*\(", published))
    for name, klass in objects.items():
        if fields.get(name) != klass:
            errors.append(f"{relative(pas)}: DFM tem {name}: {klass}, mas a classe declara {fields.get(name)}")
    for name in fields:
        if name not in objects:
            errors.append(f"{relative(pas)}: campo {name} não existe no DFM")
    for event in events:
        if event not in methods:
            errors.append(f"{relative(dfm)}: evento {event} não está publicado em {root_class}")
    if "{$R *.dfm}" not in read(pas):
        errors.append(f"{relative(pas)}: falta {{$R *.dfm}}")

# Projetos
NS = {"m": "http://schemas.microsoft.com/developer/msbuild/2003"}
projects = list(ROOT.rglob("*.dproj"))
for project in projects:
    if "build" in project.parts:
        continue
    tree = ET.parse(project)
    main = tree.find(".//m:MainSource", NS)
    if main is None or not (project.parent / main.text).exists():
        errors.append(f"{relative(project)}: MainSource inexistente")
    for reference in tree.findall(".//m:DCCReference", NS):
        target = project.parent / reference.get("Include").replace("\\", "/")
        if not target.exists():
            errors.append(f"{relative(project)}: DCCReference inexistente: {reference.get('Include')}")
    for tag in ("DCC_UnitSearchPath", "DCC_IncludePath"):
        for node in tree.findall(f".//m:{tag}", NS):
            for entry in node.text.split(";"):
                if entry and not entry.startswith("$"):
                    if not (project.parent / entry.replace("\\", "/")).is_dir():
                        errors.append(f"{relative(project)}: pasta inexistente em {tag}: {entry}")

dpr = read(ROOT / "EnterpriseFlow.dpr")
listed = {m.group(1): m.group(2) for m in re.finditer(r"(EF\.[\w.]+) in '([^']+)'", dpr)}
for unit, location in listed.items():
    if not (ROOT / location.replace("\\", "/")).exists():
        errors.append(f"EnterpriseFlow.dpr: caminho inexistente: {location}")
for path in (ROOT / "src").rglob("*.pas"):
    if path.stem not in listed and not is_fpc_only(path):
        errors.append(f"EnterpriseFlow.dpr: unidade não listada: {path.stem}")
    if path.stem in listed and is_fpc_only(path):
        errors.append(f"EnterpriseFlow.dpr: unidade só de Free Pascal listada: {path.stem}")

if errors:
    print(f"{len(errors)} problema(s):")
    print("\n".join(f"  {e}" for e in errors))
    sys.exit(1)
print(f"Regras de Delphi: {len(sources)} fontes, {len(list((ROOT / 'src').rglob('*.dfm')))} DFMs e {len(projects)} projetos sem problema.")

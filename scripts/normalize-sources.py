#!/usr/bin/env python3
"""Garante UTF-8 com BOM nos fontes Pascal com acento. Sem BOM, o Delphi le o arquivo como
ANSI e todo texto acentuado vira lixo em silencio; o Free Pascal nao acusa essa diferenca.
--check so verifica e falha (usado no CI)."""
import pathlib
import sys

BOM = b"\xef\xbb\xbf"
ROOT = pathlib.Path(__file__).resolve().parent.parent
check = "--check" in sys.argv
bad = []
for path in ROOT.rglob("*"):
    if path.suffix not in {".pas", ".dpr", ".inc", ".dfm"} or "build" in path.parts:
        continue
    data = path.read_bytes()
    body = data[len(BOM):] if data.startswith(BOM) else data
    needs_bom = any(byte >= 0x80 for byte in body)
    if needs_bom and not data.startswith(BOM):
        if check:
            bad.append(path.relative_to(ROOT))
        else:
            path.write_bytes(BOM + data)
if bad:
    print("Fontes com acento e sem BOM:", *bad, sep="\n  ")
    sys.exit(1)

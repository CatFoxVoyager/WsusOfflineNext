#!/usr/bin/env python3
# test-native-installer-strings.py
#
# DE/EN bilingual parity gate for the native installer string table
# (plan 26-02). Parses src-native/installer/strings_de_en.pas (UTF-8):
#
#   - every string id must carry a NON-EMPTY EN and DE entry
#   - the umlaut integrity strings must appear byte-exact (UTF-8) in the
#     German corpus - the plan-03 deletion precondition depends on this
#     migration being mojibake-free
#
# Prints STRINGS-GATE-PASS on success; lists the offending ids and exits
# non-zero otherwise. The au3 (Windows-1252 extraction source) stays
# untouched until this gate is green.

import re
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[2] / "src-native" / "installer" / "strings_de_en.pas"

# Pins: the plan's five required umlaut integrity strings plus the rest
# of the umlaut-bearing incumbent inventory.
UMLAUT_PINS = [
    "Wählen Sie die gewünschten Optionen",
    "Stammzertifikate aktualisieren",
    "C++-Laufzeitbibliotheken aktualisieren",
    "Alle auswählen",
    "Herunterfahren nach Abschluss",
    "Feature Update Über Enablement Package",
    "Aktualisierung",
    "Nur auditieren (Bericht fehlender Updates)",
    "Installationspakete verifizieren",
    "Microsoft Office aktualisieren",
    "Automatisch neu starten und fortsetzen",
    "Kein Office erkannt",
    ".NET Framework 3.5 installieren",
    "Steuerung",
    "MSI-Pakete",
    "Protokolldatei anzeigen",
    "Der Windows Script Host ist deaktiviert",
    "Nicht unterstütztes Betriebssystem",
    "Wählen",  # generic umlaut guard inside the intro line
]

# One record = (EN: '...'#10'...'; DE: '...'). Records are split on the
# '),' seam followed by the next '('; the last record is closed by the
# array terminator.
ARRAY_RE = re.compile(
    r"STRINGS:\s*array\[TStringId\]\s*of\s*TBilingual\s*=\s*\((.*?)\n\s*\);",
    re.DOTALL,
)
ID_LINE_RE = re.compile(r"^\s*(si[A-Za-z0-9]+)\b")
EN_DE_RE = re.compile(r"^\(?EN:\s*(.*?);\s*DE:\s*(.*)\)$", re.DOTALL)


def parse_records(block: str):
    """Split the STRINGS array body into (en_expr, de_expr) pairs."""
    chunks = re.split(r"\),\s*\(", block)
    records = []
    for i, chunk in enumerate(chunks):
        if i > 0:
            chunk = "(" + chunk
        else:
            chunk = chunk.lstrip()
            if not chunk.startswith("("):
                chunk = "(" + chunk
        if i < len(chunks) - 1:
            chunk = chunk + ")"
        # Pascal { } comments may sit between the EN/DE fields; they never
        # appear inside the string literals of this table.
        chunk = re.sub(r"\{[^}]*\}", " ", chunk)
        m = EN_DE_RE.match(chunk)
        if not m:
            continue
        records.append((m.group(1), m.group(2)))
    return records


def unquote(expr: str) -> str:
    """Join a Pascal string expression: quoted segments concatenated with
    #10-style character constants; '' inside a segment is a literal quote."""
    parts = re.findall(r"'((?:[^']|'')*)'", expr)
    text = "".join(p.replace("''", "'") for p in parts)
    return text


def main() -> int:
    if not SRC.exists():
        print(f"ERROR: strings unit not found: {SRC}", file=sys.stderr)
        return 2
    raw = SRC.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        print(f"ERROR: strings unit is not valid UTF-8: {exc}", file=sys.stderr)
        return 2

    # Extract the ordered id list from the TStringId enum.
    enum_m = re.search(r"TStringId\s*=\s*\((.*?)\);", text, re.DOTALL)
    if not enum_m:
        print("ERROR: TStringId enum not found", file=sys.stderr)
        return 2
    ids = []
    for line in enum_m.group(1).splitlines():
        m = ID_LINE_RE.match(line)
        if m:
            ids.append(m.group(1))
    if not ids:
        print("ERROR: no string ids parsed", file=sys.stderr)
        return 2

    arr_m = ARRAY_RE.search(text)
    if not arr_m:
        print("ERROR: STRINGS array not found", file=sys.stderr)
        return 2
    records = parse_records(arr_m.group(1))
    if len(records) != len(ids):
        print(
            f"ERROR: id/record count mismatch: {len(ids)} ids vs "
            f"{len(records)} records - every id needs exactly one record",
            file=sys.stderr,
        )
        return 2

    failures = []
    de_corpus = []
    en_corpus = []
    for sid, (en_expr, de_expr) in zip(ids, records):
        en = unquote(en_expr)
        de = unquote(de_expr)
        en_corpus.append(en)
        de_corpus.append(de)
        if not en.strip():
            failures.append(f"{sid}: EN empty")
        if not de.strip():
            failures.append(f"{sid}: DE empty")

    joined_de = "\n".join(de_corpus)
    joined_en = "\n".join(en_corpus)
    for pin in UMLAUT_PINS:
        if pin not in joined_de:
            failures.append(f"umlaut pin missing byte-exact in DE corpus: {pin!r}")

    if failures:
        print("STRINGS-GATE-FAIL")
        for f in failures:
            print(f"  - {f}")
        return 1

    print(f"strings unit: {len(ids)} ids, EN/DE non-empty parity OK")
    print(f"umlaut pins verified: {len(UMLAUT_PINS)} (byte-exact UTF-8)")
    print("STRINGS-GATE-PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())

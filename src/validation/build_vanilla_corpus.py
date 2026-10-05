"""Build a deterministic, source-only vanilla corpus for offline coverage.

The input is the installed game's vanilla raws, not translation dictionaries.
Selected raw fields include contextual fragments, not only complete display
queries. Generated UI, dialogue expansion and runtime adapters are not exercised.
This is a diagnostic for finding gaps; it cannot establish whole-game coverage.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

FIELD_RE = re.compile(r"\[(NAME|CASTE_NAME|DESCRIPTION|PREFSTRING|ATTACK_VERB|STATE_NAME):([^\]]+)\]")

def add(rows: dict[str, set[str]], category: str, text: str) -> None:
    # Interior spaces are part of the game's exact lookup key.
    text = text.strip()
    if not text or not re.search(r"[A-Za-z]", text):
        return
    if any(ch in text for ch in "[]{}") or text.lower() in {"n/a", "none", "unused"}:
        return
    rows.setdefault(category, set()).add(text)

def collect(root: Path) -> dict[str, set[str]]:
    rows: dict[str, set[str]] = {}
    for path in sorted(root.rglob("*.txt")):
        rel = path.relative_to(root).as_posix()
        if "/objects/" not in rel:
            continue
        group = rel.split("/", 1)[0]
        # DF vanilla raws use its legacy CP437 character set (including tile
        # bytes and comments); do not discard entire files on UTF-8 errors.
        lines = path.read_bytes().decode('cp437').splitlines()
        in_text_set = False
        for line in lines:
            if line.strip().startswith("[TEXT_SET:"):
                in_text_set = True
                continue
            for match in FIELD_RE.finditer(line):
                field, value = match.groups()
                values = value.split(":")
                if field in {"NAME", "CASTE_NAME"}:
                    for value in values[:3]:
                        add(rows, "creatures" if group.startswith("vanilla_creatures") else
                            "plants" if group == "vanilla_plants" else
                            "items" if group == "vanilla_items" else "raw_names", value)
                elif field == "DESCRIPTION":
                    add(rows, "creature_descriptions", value)
                elif field == "PREFSTRING":
                    add(rows, "preferences", value)
                elif field == "ATTACK_VERB":
                    for value in values[:2]:
                        add(rows, "combat_verbs", value)
                elif field == "STATE_NAME":
                    add(rows, "materials", values[-1])
            if group == "vanilla_text" and in_text_set and not line.strip().startswith("["):
                add(rows, "text_literals", line)
    return rows

def select(rows: dict[str, set[str]], per_category: int) -> list[dict[str, str]]:
    selected: list[dict[str, str]] = []
    for category in sorted(rows):
        values = sorted(rows[category], key=lambda value: hashlib.sha256(value.encode()).hexdigest())
        for text in values[:per_category]:
            selected.append({"page": category, "source": text})
    return selected

def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: build_vanilla_corpus.py <game-root> <output.json>")
    game_root, output = map(Path, sys.argv[1:])
    rows = collect(game_root / "data" / "vanilla")
    samples = select(rows, 120)
    counts = {key: len(value) for key, value in sorted(rows.items())}
    if len(counts) < 6 or any(counts.get(key, 0) < 20 for key in ("creatures", "items", "materials", "text_literals")):
        raise SystemExit(f"vanilla corpus unexpectedly sparse: {counts}")
    payload = {
        "version": 1,
        "source": "installed data/vanilla raws",
        "scope": "raw field/fragment diagnostic only; not whole-game or screen coverage",
        "heldOut": False,
        "limitations": ["No generated UI, personality, history or dialogue expansion",
                        "Raw fragments may require sentence context in the game",
                        "Category overlap is retained, not global deduplication",
                        "Samples inspected during development are regression data"],
        "inputSha256": {path.relative_to(game_root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                        for path in sorted((game_root / "data" / "vanilla").rglob("*.txt"))
                        if "objects" in path.parts},
        "selection": "sha256 lexical order, first 120 distinct source strings per category",
        "availableCounts": counts,
        "sampleCounts": {key: sum(row["page"] == key for row in samples) for key in counts},
        "pages": {key: {"sources": [row["source"] for row in samples if row["page"] == key]}
                  for key in sorted(counts) if any(row["page"] == key for row in samples)},
    }
    Path(output).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"availableCounts": counts, "sampleCounts": payload["sampleCounts"], "total": len(samples)}, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()

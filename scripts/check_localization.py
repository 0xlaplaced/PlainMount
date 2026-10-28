#!/usr/bin/env python3
"""Verify that application translation calls have complete Turkish catalog entries."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/MountCore/Localization.swift').read_text()
catalog = {}
for line in source.split('public static let turkish: [String: String] = [', 1)[1].split('\n    ]', 1)[0].splitlines():
    if line.strip():
        entry = json.loads('{' + line.strip().rstrip(',') + '}')
        for key in entry:
            if key in catalog:
                raise SystemExit('Duplicate translation key')
        catalog.update(entry)
calls = re.compile(r'\bL\(("(?:\\.|[^"\\])*")')
missing = []
count = 0
for path in (root / 'Sources').rglob('*.swift'):
    for match in calls.finditer(path.read_text()):
        key = json.loads(match.group(1))
        count += 1
        if key not in catalog:
            missing.append(str(path.relative_to(root)))
for key, value in catalog.items():
    if sorted(re.findall(r'%\d+\$@', key)) != sorted(re.findall(r'%\d+\$@', value)):
        raise SystemExit('Translation placeholder mismatch')
if missing:
    raise SystemExit('Missing translations in: ' + ', '.join(sorted(set(missing))))
print(f'{count}/{count} translation calls covered; {len(catalog)} bilingual catalog entries')

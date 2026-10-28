#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check_localization.py
mkdir -p .build
/usr/bin/swiftc Sources/MountCore/*.swift Tests/CoreChecks.swift -o .build/core-checks
for language in en tr; do
    echo "Core checks: $language"
    PLAINMOUNT_TEST_LANGUAGE="$language" .build/core-checks
done
/usr/bin/swiftc Sources/MountCore/*.swift Tests/LocalizationChecks.swift -o .build/localization-checks
.build/localization-checks

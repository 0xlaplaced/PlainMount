#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
/usr/bin/swiftc Sources/MountCore/*.swift Tests/CoreChecks.swift -o .build/core-checks
.build/core-checks

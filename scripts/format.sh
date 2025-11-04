#!/usr/bin/env bash
set -euo pipefail

echo "Running dart format check..."
dart format --output=none --set-exit-if-changed .
echo "Format check passed."

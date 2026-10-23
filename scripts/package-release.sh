#!/bin/bash
# Builds SpotSelector.app and zips it into build/SpotSelector.zip for a
# GitHub release. ditto keeps the code signature intact.
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build-app.sh
rm -f build/SpotSelector.zip
ditto -c -k --keepParent build/SpotSelector.app build/SpotSelector.zip
codesign --verify --strict build/SpotSelector.app
echo "Packaged build/SpotSelector.zip ($(du -h build/SpotSelector.zip | cut -f1))"

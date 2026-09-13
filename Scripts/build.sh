#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Validation
sdk="${1:-iphoneos}"
configuration="${2:-Release}"
xcodebuild -project DataGuard.xcodeproj -target DataGuard -sdk "$sdk" \
  -configuration "$configuration" CONFIGURATION_BUILD_DIR="$PWD/build/$sdk-$configuration" \
  CODE_SIGNING_ALLOWED=NO build | tee "Validation/final-$sdk-$configuration.log"

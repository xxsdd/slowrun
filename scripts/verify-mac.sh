#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --package-path RunCore
xcodebuild -project SlowRun.xcodeproj -scheme SlowRun -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath outputs/DerivedData CODE_SIGNING_ALLOWED=NO build

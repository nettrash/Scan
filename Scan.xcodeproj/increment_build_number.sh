#!/bin/bash

# Auto-increment build number script
# This script increments the build number (CFBundleVersion) automatically

# Only increment for Release builds (optional - remove this check to increment on all builds)
if [ "$CONFIGURATION" != "Release" ]; then
    echo "Skipping build number increment for non-Release build"
    exit 0
fi

# Use agvtool to increment the build number
xcrun agvtool next-version -all

echo "Build number incremented successfully"

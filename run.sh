#!/bin/bash
set -e

# Load API key from jarvis project if not already set
if [ -z "$ANTHROPIC_API_KEY" ]; then
  if [ -f "$HOME/Projects/jarvis/backend/.env" ]; then
    export $(grep ANTHROPIC_API_KEY "$HOME/Projects/jarvis/backend/.env" | xargs)
  fi
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "Error: ANTHROPIC_API_KEY not set. Add it to ~/Projects/jarvis/backend/.env or export it."
  exit 1
fi

swift build -c release

BINARY=".build/release/ClueyMac"
ENTITLEMENTS="ClueyMac.entitlements"

# Codesign with entitlements so macOS grants mic permission
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$BINARY"

ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" "$BINARY"

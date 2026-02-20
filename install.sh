#!/bin/bash
# install.sh — Install the elevate CLI to /usr/local/bin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/elevate"
TARGET="/usr/local/bin/elevate"

echo "Installing elevate CLI..."

if [[ ! -f "$SOURCE" ]]; then
    echo "Error: $SOURCE not found" >&2; exit 1
fi

if [[ ! -d /usr/local/bin ]]; then
    echo "Creating /usr/local/bin..."
    sudo mkdir -p /usr/local/bin
fi

if [[ -e "$TARGET" || -L "$TARGET" ]]; then
    echo "Replacing existing $TARGET"
    sudo rm "$TARGET"
fi

sudo ln -s "$SOURCE" "$TARGET"
echo "Linked $TARGET -> $SOURCE"

if command -v elevate >/dev/null 2>&1; then
    echo "Done. 'elevate' is now on your PATH."
else
    echo "Note: /usr/local/bin may not be in your PATH. Add it with:"
    echo "  export PATH=\"/usr/local/bin:\$PATH\""
fi

echo ""
echo "Accessibility setup:"
echo "  Ensure your terminal has Accessibility permission:"
echo "  System Settings > Privacy & Security > Accessibility"
echo ""
echo "Run 'elevate help' to get started."

#!/usr/bin/env zsh
# shellcheck shell=bash
set -euo pipefail

# Debian and Ubuntu name the binary batcat; $ZSHSETUP_HOME/bin is first on PATH, and a
# dangling link after removing bat with apt just makes bat missing again
ln -sf /usr/bin/batcat "$ZSHSETUP_HOME/bin/bat"

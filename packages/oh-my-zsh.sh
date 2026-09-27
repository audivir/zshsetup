#!/usr/bin/env zsh
# shellcheck shell=bash
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

require_cmd zsh git curl || return 1
url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
curl -fsSL "$url" | sh -s -- --unattended --keep-zshrc

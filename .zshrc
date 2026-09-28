#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
# expects $USER and $HOME to be set

# drops duplicate PATH and FPATH entries, when .zshrc is sourced again
# shellcheck disable=SC2034
typeset -U path fpath

__eprint() {
  echo "$1" >&2
  return 1
}

__assure_link() {
  local link_file expected_target
  link_file="$1"
  expected_target="$2"
  if [ -L "$link_file" ]; then
    actual_target=$(readlink "$link_file") || return 1
    if [ "$actual_target" != "$expected_target" ]; then
      __eprint "$link_file points to $actual_target. Rewriting to $expected_target..."
      ln -snf "$expected_target" "$link_file"
    fi
  elif [ -d "$link_file" ] || [ -f "$link_file" ]; then
    __eprint "$link_file is a directory or file, please backup and move it first"
  else
    ln -s "$expected_target" "$link_file"
  fi
}

__assure_dir() {
  local dir_to_check
  dir_to_check="$1"
  mkdir -p "$dir_to_check" || __eprint "$dir_to_check not found and not creatable"
}

# installs a package with the manager from ZSHSETUP_CHOICE_<PACKAGE>, ZSHSETUP_CHOICE, or a menu
# manual installs with pmg, brew and apt/apk with the names from the spec of the package
# shellcheck disable=SC2206,SC2296,SC2299
__package_manager() {
  local package choice choice_var manager name postinstall
  local -a options
  local -A names
  package="$1"
  while read -r manager name; do
    names[$manager]="$name"
  done < <(pmg external "$package" 2>/dev/null)
  options=()
  if [[ "$OSTYPE" == darwin* ]]; then
    [ -n "${names[brew]}" ] && __available brew && options+=(brew)
  else
    [ -n "${names[apt]}" ] && __available apt-get && options+=(apt)
    [ -n "${names[apk]}" ] && __available apk && options+=(apk)
    [ -n "${names[dnf]}" ] && __available dnf && options+=(dnf)
    # yum of Rocky Linux 8 and later is dnf
    [ -n "${names[yum]}" ] && __available yum && ! __available dnf && options+=(yum)
  fi
  options+=(manual)

  echo "Install $package via:" >&2
  choice_var="ZSHSETUP_CHOICE_${${package:u}//-/_}"
  choice="${(P)choice_var:-${ZSHSETUP_CHOICE:-}}"
  if [ -n "$choice" ]; then
    # an unavailable choice (e.g. apt on macOS) falls back to manual
    ((${options[(Ie)$choice]})) || choice="manual"
  elif { : </dev/tty; } 2>/dev/null; then
    PS3="choice: "
    select choice in "${options[@]}"; do
      [ -n "$choice" ] && break
    done </dev/tty >/dev/tty 2>&1
  fi
  if [ -z "$choice" ]; then
    __eprint "No install choice for $package, set ZSHSETUP_CHOICE or $choice_var"
    return 1
  fi
  echo "$choice" >&2

  if [ "$choice" = manual ]; then
    pmg install "$package" || return 1
  else
    # a spec may list several packages, e.g. "curl ca-certificates"
    # shellcheck disable=SC2086
    __system_install "$choice" ${=names[$choice]} || return 1
  fi
  [ "$choice" = apt ] && postinstall="$ZSHSETUP_HOME/packages/apt/${names[apt]%% *}.sh"
  if [ -n "$postinstall" ] && [ -f "$postinstall" ]; then
    "$postinstall" || return 1
  fi
}

# prints the last path matching a glob pattern, e.g. the dir of the newest version of a package
# shellcheck disable=SC2206,SC2296
__last_match() {
  setopt local_options null_glob
  local -a matches
  matches=(${~1})
  ((${#matches})) && echo "${matches[-1]}"
}

# checks whether pmg installed a package, for packages without a command, like glibc
__pmg_installed() {
  [ -n "$(__last_match "${PMG_HOME:-$XDG_DATA_HOME/pmg}/installed/$1@*.json")" ]
}

# installs a missing tool, warns instead of aborting and skips a failed install for a day
# ZSHSETUP_DISABLE_<PACKAGE> skips the install, but a package installed anyway (e.g. as a dependency) is used
# shellcheck disable=SC2296,SC2299
__require() {
  local package marker disable_var
  package="$1"
  marker="$ZSHSETUP_HOME/failed/$package"
  disable_var="ZSHSETUP_DISABLE_${${package:u}//-/_}"
  __available "$package" && return 0
  [ -n "${(P)disable_var}" ] && return 1
  __pmg_installed "$package" && return 0
  # the marker holds the time of the failure
  local failed_at
  zmodload zsh/datetime
  if [ -f "$marker" ]; then
    failed_at="$(<"$marker")"
    case "$failed_at" in
      "" | *[!0-9]*) failed_at=0 ;;
    esac
    ((EPOCHSECONDS - failed_at < 86400)) && return 1
  fi
  # rehash, as zsh would otherwise keep running a command it found before
  if __package_manager "$package" && rehash && { __available "$package" || __pmg_installed "$package"; }; then
    . "${PMG_HOME:-$XDG_DATA_HOME/pmg}/env.sh" 2>/dev/null
    rm -f "$marker"
    return 0
  fi
  mkdir -p "${marker%/*}" && echo "$EPOCHSECONDS" >"$marker"
  __eprint "zshsetup: installing $package failed, skipping it for a day (retry with install_manual $package)"
}

__source() {
  local env
  env=$("$@") || return 1
  eval "$env"
}

__init_cache() {
  local user_cache scratch_cache
  user_cache="$HOME/.cache"
  scratch_cache="/scratch/$USER/.cache"
  # if /home is mounted, looks for /scratch to use as cache directory
  if [ -z "$ZSHSETUP_IGNORESCRATCH" ] && [ -d "/scratch" ] \
    && [ ! -f "$user_cache/.zshsetup_do_not_use_scratch" ]; then
    if [ -d "$user_cache" ] && [ ! -L "$user_cache" ]; then
      __eprint "zshsetup stopped: /scratch exists, but $user_cache is a directory.
Move it to /scratch with:
  mkdir -p ${scratch_cache:h} && mv $user_cache $scratch_cache
or keep it with:
  touch $user_cache/.zshsetup_do_not_use_scratch"
      return 1
    fi
    __assure_dir "$scratch_cache" || return 1
    __assure_link "$user_cache" "$scratch_cache" || return 1
  fi
}

# inits the environment before running any failable commands
__init_zshsetup_env() {
  export ZSHSETUP_REPO="${ZSHSETUP_REPO:-https://github.com/audivir/zshsetup}"
  export ZSHSETUP_HOME="$HOME/.config/zshsetup"

  # SETUP XDG SPEC
  export LOCAL_HOME="$HOME/.local"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$LOCAL_HOME/share"
  export XDG_BIN_HOME="$LOCAL_HOME/bin"
  export XDG_CACHE_HOME="$HOME/.cache"
  export XDG_STATE_HOME="$LOCAL_HOME/state"

  # systemd / macOS runtime dir
  if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    if [ -d "/run/user/$UID" ]; then
      export XDG_RUNTIME_DIR="/run/user/$UID"
    elif [[ "$OSTYPE" == darwin* ]] && [ -n "$TMPDIR" ]; then
      export XDG_RUNTIME_DIR="${TMPDIR%/}"
    fi
  fi

  # SETUP HISTORY
  HISTFILE="$ZSHSETUP_HOME/zsh_history"
  HISTSIZE=50000
  # shellcheck disable=SC2034
  SAVEHIST=1000

  # SETUP OH-MY-ZSH
  export ZSH="$ZSHSETUP_HOME/oh-my-zsh"
  # shellcheck disable=SC2034
  plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
  ZSH_CACHE_DIR="$XDG_CACHE_HOME/zsh"
  # shellcheck disable=SC2034
  ZSH_COMPDUMP="$ZSH_CACHE_DIR/zcompdump-${HOST%%.*}-${ZSH_VERSION}"
  # shellcheck disable=SC2034
  ZSH_CUSTOM="$ZSH/custom"
  # shellcheck disable=SC2034
  ZSH_THEME="robbyrussell"

  # SETUP PATH
  PATH="$ZSHSETUP_HOME/bin:$XDG_BIN_HOME:$HOME/bin:$PATH"

  # SETUP OTHER ENVIRONMENT
  export GNUPGHOME="$XDG_DATA_HOME/gnupg"
  export MPLCONFIGDIR="$XDG_CONFIG_HOME/matplotlib"
  export PYTHON_HISTORY="$XDG_DATA_HOME/python/python_history"
  # without system certificates, git and micromamba use the ones bundled with git-static
  local git_certs
  git_certs="$(__last_match "$XDG_DATA_HOME/git@*/share/git-core/certs")"
  if [ ! -e /etc/ssl/cert.pem ] && [ -z "$(ls -A /etc/ssl/certs 2>/dev/null)" ] && [ -n "$git_certs" ]; then
    export GIT_SSL_CAPATH="$git_certs"
    export MAMBA_SSL_VERIFY="$GIT_SSL_CAPATH/cacert.pem"
  fi
}

# runs the setup functions
__init_zshsetup() {
  # __available, __system_install, and the other functions shared with install.sh and packages/pmg
  # shellcheck disable=SC2016
  ZSHSETUP_INSTALL_LIB=1 emulate sh -c '. "$ZSHSETUP_HOME/install.sh"' || return 1
  __init_cache || return 1

  local dir
  for dir in "$LOCAL_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_BIN_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" \
    "$ZSHSETUP_HOME/bin"; do
    __assure_dir "$dir" || return 1
  done

  # BEGIN PMG
  # pmg installs the packages, see packages/pmg; completions call it by name, so it is linked into PATH
  __assure_link "$ZSHSETUP_HOME/bin/pmg" "$ZSHSETUP_HOME/packages/pmg" || return 1
  # the completions pmg installs, and that of pmg itself, before oh-my-zsh runs compinit
  fpath=("$XDG_DATA_HOME/zsh/site-functions" "${fpath[@]}")
  # pmg writes its completion whenever it changes something, a system without changes gets it here
  [ -f "$XDG_DATA_HOME/zsh/site-functions/_pmg" ] || pmg completion >"$XDG_DATA_HOME/zsh/site-functions/_pmg"
  # mandoc (Alpine) does not find man pages next to the bin dirs in PATH, the trailing colon keeps the defaults
  export MANPATH="$XDG_DATA_HOME/man:"
  # the environment and PATH entries of packages like go and rustup
  [ -f "${PMG_HOME:-$XDG_DATA_HOME/pmg}/env.sh" ] && . "${PMG_HOME:-$XDG_DATA_HOME/pmg}/env.sh"
  # END PMG

  # BEGIN CURL AND GIT
  # oh-my-zsh installs with both
  __require curl
  __require git
  # END CURL AND GIT

  # BEGIN OH-MY-ZSH
  if [ ! -d "$ZSH" ]; then
    "$ZSHSETUP_HOME/packages/oh-my-zsh.sh" || return 1
  fi
  __assure_dir "$ZSH_CACHE_DIR" || return 1
  # shellcheck disable=SC2034
  . "$ZSH/oh-my-zsh.sh" || return 1
  # END OH-MY-ZSH

  # BEGIN HOMEBREW
  if [ -f "/opt/homebrew/bin/brew" ]; then
    __source /opt/homebrew/bin/brew shellenv || return 1
    alias homebrewupdate='brew update; brew upgrade --formulae --yes && brew cu --yes && cd /opt/homebrew && git stash pop &>/dev/null || true && cd -'
  fi
  # BEGIN PYTHON
  __require uv
  # a uv in PATH replaces the one packages/pmg bootstrapped for itself
  __available uv && rm -rf "$XDG_CACHE_HOME/zshsetup/uv"
  if __require uvc; then
    __source command uvc shell zsh
  fi
  # END PYTHON

  # BEGIN JQ
  __require jq
  # END JQ

  # BEGIN GAWK
  __require gawk
  # END GAWK
  #
  # BEGIN MICROMAMBA
  # micromamba and conda-forge packages need glibc, see packages/musl/micromamba
  if { [ -n "$ZSHSETUP_REQUIRE_MICROMAMBA" ] || { [ ! -e /lib/ld-musl-x86_64.so.1 ] && [ ! -e /lib/ld-musl-aarch64.so.1 ]; }; } \
    && __require micromamba; then
    alias conda='micromamba'
    export MAMBA_ROOT_PREFIX="$XDG_DATA_HOME/micromamba"
    local real_exe
    real_exe="$(__last_match "$XDG_DATA_HOME/micromamba@*/micromamba")"
    if [ -n "$real_exe" ]; then
      # on musl, the hook calls the real binary by path, but the wrapper also patches new programs for glibc
      local hook
      hook="$(command micromamba shell hook --shell zsh)" && eval "${hook//$real_exe/$XDG_BIN_HOME/micromamba}"
    else
      __source command micromamba shell hook --shell zsh
    fi
  fi
  # END MICROMAMBA

  # BEGIN GO
  # for go from other package managers, pmg sets GOROOT, GOPATH, and PATH in its env file
  export GOPATH="${GOPATH:-$XDG_DATA_HOME/go}"
  PATH="$GOPATH/bin:$PATH"
  __require go
  # END GO

  # BEGIN RUST
  # for rustup from other package managers, pmg sets RUSTUP_HOME, CARGO_HOME, and PATH in its env file
  export RUSTUP_HOME="${RUSTUP_HOME:-$XDG_DATA_HOME/rustup}"
  export CARGO_HOME="${CARGO_HOME:-$XDG_DATA_HOME/cargo}"
  PATH="$CARGO_HOME/bin:/opt/homebrew/opt/rustup/bin:$PATH"
  __require rustup
  # the cc of pmg is zig, which links musl programs itself
  if [[ "$(whence -p cc)" == "$XDG_BIN_HOME/cc" ]] && [ -e "/lib/ld-musl-$(uname -m).so.1" ]; then
    export "CARGO_TARGET_$(uname -m | tr '[:lower:]' '[:upper:]')_UNKNOWN_LINUX_MUSL_RUSTFLAGS=-C link-self-contained=no"
  fi
  # musl toolchains need libgcc_s
  local musl_libs
  musl_libs="$(__last_match "$XDG_DATA_HOME/musl-libs@*/usr/lib")"
  if [ -n "$musl_libs" ] && [ ! -e /usr/lib/libgcc_s.so.1 ]; then
    export LD_LIBRARY_PATH="$musl_libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  fi
  # END RUST

  # BEGIN REQUIRED PACKAGES
  # non-default packages from ZSHSETUP_REQUIRE_<PACKAGE>, e.g. ZSHSETUP_REQUIRE_ZIG
  local required_var
  # shellcheck disable=SC2296
  for required_var in ${(k)parameters[(I)ZSHSETUP_REQUIRE_*]}; do
    # shellcheck disable=SC2296,SC2299
    [ -n "${(P)required_var}" ] && __require "${${${required_var#ZSHSETUP_REQUIRE_}:l}//_/-}"
  done
  # END REQUIRED PACKAGES

  # BEGIN JAVASCRIPT
  export BUN_INSTALL="$XDG_DATA_HOME/bun"
  export BUN_INSTALL_CACHE_DIR="$XDG_CACHE_HOME/bun/install"
  export BUN_RUNTIME_TRANSPILER_CACHE_PATH="$XDG_CACHE_HOME/bun/runtime"
  export BUN_CONFIG_DIR="$XDG_CONFIG_HOME/bun"
  PATH="$BUN_INSTALL/bin:$PATH"
  __require bun
  # END JAVASCRIPT

  # BEGIN EXTRA TOOLS
  __require bat
  __require micro
  __require kv
  # END EXTRA TOOLS

  # the metadata of apt, dnf, and yum that installs downloaded onto a system without any
  __clean_metadata

  # BEGIN ALIASES
  alias b="bat --paging=never --style=plain --tabs=4"
  alias sb="sudo bat --paging=never --style=plain --tabs=4"
  # END ALIASES

  # zshsetup's own links (e.g. bat -> batcat) come first
  # typeset -U only deduplicates array assignments, not PATH="...:$PATH"
  path=("$ZSHSETUP_HOME/bin" "${path[@]}")
  export PATH

  # BEGIN THEME VIEWER
  . "$ZSHSETUP_HOME/theme_viewer.sh" || return 1
  # END THEME VIEWER

  # BEGIN CUSTOM FUNCTIONS
  . "$ZSHSETUP_HOME/custom_functions.sh" || return 1
  # END CUSTOM FUNCTIONS
}

# keeps the ZSHSETUP_* settings and the toolchain of pmg given at installation for later shells
# shellcheck disable=SC2296
__save_settings() {
  local preinit var
  preinit="$ZSHSETUP_HOME/preinit.zsh"
  if [ ! -f "$preinit" ]; then
    printf '#!/usr/bin/env zsh\n# shellcheck shell=bash\n' >"$preinit" || return 1
    chmod +x "$preinit" || return 1
  fi
  for var in ZSHSETUP_CHOICE ${(k)parameters[(I)ZSHSETUP_CHOICE_*]} ${(k)parameters[(I)ZSHSETUP_REQUIRE_*]} \
    ${(k)parameters[(I)ZSHSETUP_DISABLE_*]} ZSHSETUP_IGNORESCRATCH PMG_RUST_TOOLCHAIN; do
    if [ -n "${(P)var}" ]; then
      echo "export $var=${(q)${(P)var}}" >>"$preinit" || return 1
    fi
  done
}

# installs zshsetup from github
__install_zshsetup() {
  if [ -d "$ZSHSETUP_HOME" ]; then
    __assure_link "$HOME/.zshrc" "$ZSHSETUP_HOME/.zshrc" || return 1
    __eprint "$ZSHSETUP_HOME already exists, updating instead"
    update_zshsetup
    return 0
  fi
  trap 'rm -rf "$ZSHSETUP_HOME"' EXIT INT TERM
  if ! git clone "$ZSHSETUP_REPO" "$ZSHSETUP_HOME"; then
    __eprint "Failed to clone $ZSHSETUP_REPO to $ZSHSETUP_HOME"
    return 1
  fi
  if ! __assure_link "$HOME/.zshrc" "$ZSHSETUP_HOME/.zshrc"; then
    __eprint "Failed to link .zshrc"
    return 1
  fi
  if ! __save_settings; then
    __eprint "Failed to save settings to preinit.zsh"
    return 1
  fi
  if ! __init_zshsetup; then
    __eprint "Failed to initialize zsh"
    return 1
  fi
  trap - EXIT INT TERM
  __eprint "zshsetup installed and linked"
  return 0
}

# updates zshsetup itself and all packages
update_zshsetup() {
  if [ ! -d "$ZSHSETUP_HOME" ]; then
    __eprint "$ZSHSETUP_HOME does not exist, installing instead"
    __install_zshsetup
    return "$?"
  fi
  (
    cd "$ZSHSETUP_HOME" || exit 1
    git fetch || __eprint "Failed to fetch new data from $ZSHSETUP_REPO"
    git merge || __eprint "Failed to merge updates"
  )

  rm -rf "$ZSHSETUP_HOME/failed"

  pmg update || __eprint "Failed to update the specs of pmg"
  pmg upgrade || __eprint "Failed to upgrade the packages of pmg"

  # omz only exists once oh-my-zsh is sourced, so run its upgrade script directly
  local omz_dir omz_cache
  omz_dir="${ZSH:-$ZSHSETUP_HOME/oh-my-zsh}"
  [ -f "$omz_dir/tools/upgrade.sh" ] || return 0
  ZSH="$omz_dir" zsh -f "$omz_dir/tools/upgrade.sh" -v default || __eprint "Failed to update oh-my-zsh"
  # keeps oh-my-zsh from asking to update again, like omz update does
  zmodload zsh/datetime
  omz_cache="${ZSH_CACHE_DIR:-$omz_dir/cache}"
  mkdir -p "$omz_cache" && echo "LAST_EPOCH=$((EPOCHSECONDS / 60 / 60 / 24))" >|"$omz_cache/.zsh-update"
}

# installs packages with pmg, see pmg --help for all its commands
install_manual() {
  local p
  for p in "$@"; do
    rm -f "$ZSHSETUP_HOME/failed/$p"
  done
  pmg install "$@" && rehash
}

# uninstalls packages with pmg
uninstall_manual() {
  pmg uninstall "$@" && rehash
}

# edits pre- or post-init files with $EDITOR or micro
edit_zshsetup() {
  local target
  case "${1:-pre}" in
    pre)
      target="$ZSHSETUP_HOME/preinit.zsh"
      ;;
    post)
      target="$ZSHSETUP_HOME/postinit.zsh"
      ;;
    *)
      __eprint "Usage: edit_zshsetup <pre|post>"
      return 1
      ;;
  esac
  if [ ! -f "$target" ]; then
    printf '#!/usr/bin/env zsh\n# shellcheck shell=bash\n' >"$target" || return 1
    chmod +x "$target" || return 1
  fi
  ${=EDITOR:-micro} "$target"
}

# runs cli commands or displays usage
run_zshsetup() {
  case "$1" in
    install)
      __install_zshsetup
      ;;
    update)
      update_zshsetup
      ;;
    *)
      __eprint "Usage: run_zshsetup <install|update>"
      return 1
      ;;
  esac
}

# INITIALIZE ENVIRONMENT
__init_zshsetup_env

# CLI
if [ "$#" -gt 0 ]; then
  run_zshsetup "$@"
  exit "$?"
fi

# SOURCE PRE-INIT
if [ ! -f "$ZSHSETUP_HOME/preinit.zsh" ]; then
  printf '#!/usr/bin/env zsh\n# shellcheck shell=bash\n' >"$ZSHSETUP_HOME/preinit.zsh" || return 1
  chmod +x "$ZSHSETUP_HOME/preinit.zsh" || return 1
fi
. "$ZSHSETUP_HOME/preinit.zsh" || return 1

# INITIALIZE DIRECTORIES/OMZ/PACKAGES
__init_zshsetup || return 1

# SOURCE POST-INIT
if [ ! -f "$ZSHSETUP_HOME/postinit.zsh" ]; then
  printf '#!/usr/bin/env zsh\n# shellcheck shell=bash\n' >"$ZSHSETUP_HOME/postinit.zsh" || return 1
  chmod +x "$ZSHSETUP_HOME/postinit.zsh" || return 1
fi
. "$ZSHSETUP_HOME/postinit.zsh" || return 1

# CLEANUP
unfunction __assure_link __assure_dir __package_manager __last_match __pmg_installed __require __source
unfunction __init_cache __init_zshsetup_env __init_zshsetup __install_zshsetup __save_settings
unfunction __which __available __download __uv_libc __bootstrap_uv __has_metadata __system_install __clean_metadata
unfunction __install_chosen __install_main
unset __PMG_TAG __METADATA_CREATED

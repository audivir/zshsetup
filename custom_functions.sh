#!/usr/bin/env bash

# overrides rm to check for mounts before running the command
rm() {
  local arg root mounts target hits after_options

  after_options=false
  mounts=""

  for arg in "$@"; do
    if ! $after_options; then
      case "$arg" in
        --)
          after_options=true
          continue
          ;;
        -*)
          continue
          ;;
      esac
    fi

    [[ -e "$arg" || -L "$arg" ]] || continue

    # rm deletes a symlink itself, so only its parent directory is resolved
    if [[ -L "$arg" && "$arg" != */ ]]; then
      root="${arg:h:A}"
      root="${root%/}/${arg:t}"
    else
      root="${arg:A}"
    fi

    # fetches all mount targets once depending on the OS
    if [[ -z "$mounts" ]]; then
      mounts=$(
        if command -v findmnt >/dev/null 2>&1; then
          findmnt -rn -o TARGET
        else
          mount | awk 'match($0, / on \/.* \(/) { print substr($0, RSTART+4, RLENGTH-6) }'
        fi
      )
    fi

    hits=""
    while IFS= read -r target; do
      if [[ "$target" == "$root" || ("$root" != "/" && "$target" == "$root"/*) ]]; then
        hits+="$target"$'\n'
      fi
    done <<<"$mounts"

    if [[ -n "$hits" ]]; then
      printf 'rm: refusing to remove %q\n' "$arg" >&2
      printf 'rm: mounted filesystem(s):\n%s' "$hits" >&2
      return 1
    fi
  done

  /bin/rm "$@"
}

# shows the history with parsed unix timestamps
showhist() {
  # zsh stores non-ASCII history as metafied bytes, which are no valid UTF-8
  LC_ALL=C gawk 'match($0, /^: ([0-9]+):([0-9]+);/, m) {
    print strftime("%Y-%m-%d %H:%M:%S", m[1]) ":" m[2] ";" substr($0, RLENGTH + 1)
    next
  }
  { print }' "$HISTFILE"
}

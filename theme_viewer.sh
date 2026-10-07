#!/usr/bin/env zsh
# shellcheck shell=bash

update_theme() {
  # an LC_THEME not set by update_theme wins (e.g. forwarded over SSH or exported by hand).
  # unsetting LC_THEME returns to the detected theme.
  [ -n "$LC_THEME" ] && [ "$LC_THEME" != "$ZSHSETUP_DETECTED_THEME" ] && return 0
  if [ -z "$SSH_CONNECTION" ] && [[ "$OSTYPE" == darwin* ]]; then
    # macOS: check dark mode
    defaults read -g AppleInterfaceStyle >/dev/null 2>&1
  else
    # elsewhere: night time (19-7 => dark). a zero system offset, as with UTC (the default of most
    # containers) or a TZ without tzdata, is replaced by the zone file of TZ in the TZDIR of pmg,
    # else by the UTC offset of the IP address, which is cached for a day.
    local hour system_offset tz_file="" offset=0 cached_at=0
    local cache="${XDG_CACHE_HOME:-$HOME/.cache}/zshsetup/utc_offset"
    zmodload zsh/datetime
    strftime -s system_offset %z "$EPOCHSECONDS"
    case "$TZ" in
      "" | UTC | Etc/UTC | :* | /*) ;;
      *) [ -n "$TZDIR" ] && [ -f "$TZDIR/$TZ" ] && tz_file="$TZDIR/$TZ" ;;
    esac
    if [ "$system_offset" = "+0000" ] && [ -n "$tz_file" ]; then
      # musl ignores TZDIR, but reads the path of a zone file in TZ, here only for this date call.
      hour=$(TZ="$tz_file" date +%H)
      hour=${hour#0}
    elif [ "$system_offset" = "+0000" ]; then
      [ -f "$cache" ] && read -r cached_at offset <"$cache"
      case "$cached_at" in
        "" | *[!0-9]*) cached_at=0 ;;
      esac
      if ((EPOCHSECONDS - cached_at >= 86400)) && command -v curl >/dev/null 2>&1; then
        offset=$(curl -fsSL --connect-timeout 2 --max-time 3 \
          "http://ip-api.com/line?fields=offset" 2>/dev/null)
        # a failed lookup is cached as well, so it does not delay every shell.
        mkdir -p "${cache%/*}" && echo "$EPOCHSECONDS $offset" >|"$cache"
      fi
      case "${offset#-}" in
        "" | *[!0-9]*) offset=0 ;;
      esac
      hour=$(((EPOCHSECONDS + offset) / 3600 % 24))
    else
      strftime -s hour %H "$EPOCHSECONDS"
      hour=${hour#0}
    fi
    [ "${hour:-0}" -lt 7 ] || [ "${hour:-0}" -ge 19 ]
  fi
  # shellcheck disable=SC2181
  [ $? -eq 0 ] && LC_THEME="dark" || LC_THEME="light"
  export LC_THEME ZSHSETUP_DETECTED_THEME="$LC_THEME"
}

__init_theme_viewer() {
  # format: app|light_theme|dark_theme|command_with_placeholder
  # use [] as placeholder
  local apps="${THEMEABLE_APPS:-
micro|sunny-day|one-dark|micro --colorscheme
bat|Monokai Extended Light|Monokai Extended|bat --theme
kv|light|dark|kv --theme
}"

  local app light dark template
  while IFS='|' read -r app light dark template; do
    [ -z "$app" ] && continue

    # skip apps that are not installed, like kv, which is only installed when required
    command -v "$app" >/dev/null || continue

    eval "\
$app() {
  local theme
  update_theme
  if [[ \"\$LC_THEME\" == 'light' ]]; then
    theme=\"$light\"
  else
    theme=\"$dark\"
  fi
  command $template \"\$theme\" \"\$@\"
}
s$app() {
  local theme
  update_theme
  if [[ \"\$LC_THEME\" == 'light' ]]; then
    theme=\"$light\"
  else
    theme=\"$dark\"
  fi
  sudo $template \"\$theme\" \"\$@\"
}
  "
  done <<EOF
$apps
EOF

  update_theme

  ssh() {
    update_theme
    command ssh -o SendEnv=LC_THEME "$@"
  }
}

__init_theme_viewer
unfunction __init_theme_viewer

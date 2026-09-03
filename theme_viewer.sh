#!/usr/bin/env sh
_LINUX_WARNING=0
# macOS: check dark mode
_is_dark_darwin() {
  defaults read -g AppleInterfaceStyle >/dev/null 2>&1
}

# Linux: not yet implemented, falls back to time of day
_is_dark_linux() {
 if [ "$_LINUX_WARNING" -eq 0 ]; then
   echo "Dark mode checking for Linux is not yet implemented. Defaulting to time of day." >&2
   _LINUX_WARNING=1
 fi
 _is_time_for_dark
}

# Detect dark mode
_is_dark() {
  _desktop=""

  if [ "$(uname)" = "Darwin" ]; then
    _is_dark_darwin
  else
    _desktop=$(echo "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')
    case "$_desktop" in
      *gnome*)
        _is_dark_linux
        ;;
      *kde*)
        _is_dark_linux
         ;;
      *)
        _is_dark_linux
        ;;
    esac
  fi
}

# Set LC_THEME to dark if input is true
_set_theme() {
  if [ "$1" -eq 0 ]; then
    LC_THEME="dark"
  else
    LC_THEME="light"
  fi
  export LC_THEME
}

# Detect local night time (19-7 => dark)
_is_time_for_dark() {
  _hour=$(date +%H)
  _hour=${_hour#0}
  _hour=${_hour:-0}
  [ "$_hour" -lt 7 ] || [ "$_hour" -gt 19 ]
}

# Update theme:
# locally: detect dark mode
# over SSH: keep the forwarded LC_THEME, falling back to time of day if unset
_update_theme() {
  if [ -z "$SSH_CONNECTION" ]; then
    _is_dark
    _set_theme "$?"
  elif [ -z "$LC_THEME" ]; then
    _is_time_for_dark
    _set_theme "$?"
  fi
}

# Check if current theme is light
_use_light_theme() {
  _update_theme
  [ "$LC_THEME" = "light" ]
}

# Format: app|light_theme|dark_theme|command_with_placeholder
# use [] as placeholder
THEMEABLE_APPS="
micro|sunny-day|one-dark|micro --colorscheme
bat|Monokai Extended Light|Monokai Extended|bat --theme
"

while IFS='|' read -r _app _light _dark _template; do
  [ -z "$_app" ] && continue

  # skip if app is not installed
  if ! command -v "$_app" >/dev/null; then
      echo "$_app not found, cannot create themed functions" >&2
      continue
  fi

  eval "\
    $_app() {
      if _use_light_theme; then
        _theme=\"$_light\"
      else
        _theme=\"$_dark\"
      fi
      command $_template \"\$_theme\" \"\$@\"
    }
    s$_app() {
      if _use_light_theme; then
        _theme=\"$_light\"
      else
        _theme=\"$_dark\"
      fi
      sudo $_template \"\$_theme\" \"\$@\"
    }
"
done <<EOF
$THEMEABLE_APPS
EOF

_update_theme

ssh() {
  _update_theme
  command ssh -o SendEnv=LC_THEME "$@"
}

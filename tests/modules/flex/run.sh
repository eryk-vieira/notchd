#!/bin/sh
# A user module for the visual scenarios (tests/visual/shell.qml,
# "module-user-dark"): settings with long help texts and long options, no
# view.
read -r init
while read -r line; do
  case "$line" in
    *'"t":"stop"'*) exit 0 ;;
  esac
done

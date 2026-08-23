#!/bin/zsh
# Compatibility entry point for users of the former Native Local script.
exec "${0:A:h}/build-hikari.sh" "$@"

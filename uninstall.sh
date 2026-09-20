#!/bin/sh
# Remove everything install.sh put in place: the skills, the rules block
# between the reethink markers, and the hook entry. Nothing else in any file it
# touched is changed.
#
#   sh uninstall.sh            remove from every agent found
#   sh uninstall.sh --dry-run  print the plan, change nothing
#   sh uninstall.sh --agent claude-code
#
# reethink, by ree_es97 (https://reetech.web.id)
# MIT licensed. https://github.com/masbrokemanaaja/reethink
set -eu
dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
exec sh "$dir/install.sh" --uninstall "$@"

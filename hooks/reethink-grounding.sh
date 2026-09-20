#!/bin/sh
# reethink, by ree_es97 (https://reetech.web.id)
# MIT licensed. https://github.com/masbrokemanaaja/reethink
#
# Wrapper so a host that cannot run Python directly still gets valid JSON.
# Must always print one object and never hang.
#
# A failure here used to be invisible: stderr went to /dev/null and the fallback
# was printed with nothing written down, so the log showed no line at all and
# the troubleshooting guide then sent you looking at the agent's config. The
# reminder is still never worth breaking a turn over, but the reason it did not
# arrive belongs in the log.
dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || dir=.
err="${TMPDIR:-/tmp}/reethink-hook.$$"
out=$(python3 "$dir/reethink_grounding.py" 2>"$err")
status=$?

if [ "$status" -ne 0 ] || [ -z "$out" ]; then
  reason=$(tr '\n' ' ' < "$err" 2>/dev/null | cut -c1-200)
  [ -n "$reason" ] || reason="python3 exited $status with no message"
  if mkdir -p "$HOME/.reethink" 2>/dev/null; then
    printf '%s wrapper: no injection, %s\n' \
      "$(date +%Y-%m-%dT%H:%M:%S)" "$reason" >> "$HOME/.reethink/hooks.log" 2>/dev/null
  fi
  out='{}'
fi

rm -f "$err"
printf '%s\n' "$out"

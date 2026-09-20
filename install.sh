#!/bin/sh
# reethink installer.
#
# Detects the agents installed on this machine and puts three things in place
# for each one it knows how to reach:
#
#   skills  the Agent Skills folders, copied to that agent's skills directory
#   rules   a routing block inserted into that agent's global instruction file
#   hook    a first-turn grounding reminder, where the agent supports hooks
#
# Everything it writes is marked and reversible: rule blocks sit between
# reethink markers, hook entries carry a reethink id, and uninstall.sh removes
# exactly those. Nothing else in a file it touches is rewritten.
#
#   sh install.sh                 install everything it can
#   sh install.sh --dry-run       print the plan, change nothing
#   sh install.sh --skills-only   skip rules and hooks
#   sh install.sh --agent claude-code   one agent: claude-code, codex, antigravity
#   sh install.sh --list          show what was detected
#   sh install.sh --uninstall     same as uninstall.sh
#   sh install.sh --version       print the version and exit
#
# REETHINK_REF pins what the piped-from-curl install downloads, by tag or by
# branch. It defaults to main and is ignored when running from a clone.
#
# reethink, by ree_es97 (https://reetech.web.id)
# MIT licensed. https://github.com/masbrokemanaaja/reethink

set -eu

VERSION="1.0.0"
MARK_START="<!-- reethink:start -->"
MARK_END="<!-- reethink:end -->"

DRY=0
SKILLS_ONLY=0
ONLY_AGENT=""
ACTION="install"

SRC=""
RED=""; GREEN=""; YELLOW=""; DIM=""; BOLD=""; OFF=""
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  RED=$(printf '\033[31m'); GREEN=$(printf '\033[32m'); YELLOW=$(printf '\033[33m')
  DIM=$(printf '\033[2m'); BOLD=$(printf '\033[1m'); OFF=$(printf '\033[0m')
fi

say()  { printf '%s\n' "$*"; }
ok()   { printf '  %s+%s %s\n' "$GREEN" "$OFF" "$*"; }
skip() { printf '  %s.%s %s%s%s\n' "$DIM" "$OFF" "$DIM" "$*" "$OFF"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$OFF" "$*"; }
die()  { printf '%serror:%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

usage() {
  # The header comment, and nothing past it. A fixed line range overran the
  # comment and printed the first lines of the script itself.
  if [ -f "$0" ]; then
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
  else
    say "reethink installer, by ree_es97. https://github.com/masbrokemanaaja/reethink"
    say "  --dry-run  --skills-only  --agent <id>  --list  --uninstall  --version"
  fi
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY=1 ;;
    --skills-only) SKILLS_ONLY=1 ;;
    --agent) shift; { [ $# -gt 0 ] && [ -n "$1" ]; } || die "--agent needs a name"; ONLY_AGENT="$1" ;;
    --list) ACTION="list" ;;
    --uninstall) ACTION="uninstall" ;;
    --version) say "reethink $VERSION by ree_es97 (https://reetech.web.id)"; exit 0 ;;
    -h|--help) usage ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

# --- where this package lives -----------------------------------------------
# Run from a clone, or piped from curl in which case fetch the tarball first.
resolve_source() {
  # $0 is only a usable path when this ran as a file. Piped from curl it is
  # "sh", whose dirname is ".", and the check below would then install from
  # whatever happens to sit in the current directory instead of downloading.
  script_dir=""
  if [ -f "$0" ]; then
    if script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P); then
      :
    else
      script_dir=""
    fi
  fi
  if [ -n "$script_dir" ] && [ -d "$script_dir/skills" ] && [ -f "$script_dir/install.sh" ]; then
    SRC="$script_dir"
    return
  fi
  command -v curl >/dev/null 2>&1 || die "no local copy found and curl is not installed"
  SRC=$(mktemp -d) || die "cannot create a temporary directory"
  trap 'rm -rf "$SRC"' EXIT INT TERM
  # Whatever is on main, unless you pin it: REETHINK_REF=v1.0.0 sh install.sh
  ref="${REETHINK_REF:-main}"
  say "${DIM}fetching reethink ($ref)...${OFF}"
  curl -fsSL "https://codeload.github.com/masbrokemanaaja/reethink/tar.gz/$ref" \
    | tar -xzf - -C "$SRC" --strip-components=1 \
    || die "download failed"
  [ -d "$SRC/skills" ] || die "downloaded archive has no skills directory"
}

# --- the agents we know how to reach ----------------------------------------
# One record per target: id | display name | a path that proves it is there |
# skills dir | global instruction file | hook style. A field of "none" means
# the target has no such thing and that step is skipped.
#
# Paths are the ones each agent documents for personal, machine-wide config.
# Google ships three of these and they do not share a layout. Antigravity and
# Antigravity IDE both read ~/.gemini/config, which is why one row covers them
# both; the ~/.gemini/antigravity and ~/.gemini/antigravity-ide directories
# beside it hold per-app state, no skills and no hooks. Gemini CLI is separate
# again: ~/.gemini/skills, and ~/.gemini/settings.json is what proves it is
# installed, since ~/.gemini alone exists as soon as Antigravity does. It does
# share ~/.gemini/GEMINI.md with Antigravity, and the block is written between
# markers, so whichever row gets there first is the only copy.
#
# The last two rows are not agents. ~/.agents/skills is the cross-tool alias:
# Gemini CLI documents it beside ~/.gemini/skills, Codex documents it as its
# user scope, and Cursor lists it as well, so one directory reaches all three
# without a row each. ~/.cursor/skills is Cursor's own. Neither has a global
# instruction file this package has verified, so neither takes a rules block.
AGENTS="claude-code|Claude Code|$HOME/.claude|$HOME/.claude/skills|$HOME/.claude/CLAUDE.md|claude-code
antigravity|Antigravity|$HOME/.gemini/config|$HOME/.gemini/config/skills|$HOME/.gemini/GEMINI.md|antigravity
codex|Codex|$HOME/.codex|$HOME/.codex/skills|$HOME/.codex/AGENTS.md|codex
gemini-cli|Gemini CLI|$HOME/.gemini/settings.json|$HOME/.gemini/skills|$HOME/.gemini/GEMINI.md|none
agents-dir|Shared skills directory|$HOME/.agents|$HOME/.agents/skills|none|none
cursor|Cursor|$HOME/.cursor|$HOME/.cursor/skills|none|none"

field() { printf '%s' "$1" | cut -d'|' -f"$2"; }

# A name that is not in the table has to fail here. Skipping every record and
# then printing the closing "Restart your agent" line would report a successful
# install after writing nothing at all.
if [ -n "$ONLY_AGENT" ]; then
  known=$(printf '%s\n' "$AGENTS" | cut -d'|' -f1 | tr '\n' ' ')
  case " $known " in
    *" $ONLY_AGENT "*) ;;
    *) die "unknown agent: $ONLY_AGENT (known: ${known% })" ;;
  esac
fi

detected_any=0

# --- skills ------------------------------------------------------------------
install_skills() {
  target="$1"
  for dir in "$SRC"/skills/*/; do
    name=$(basename "$dir")
    if [ "$DRY" = 1 ]; then
      skip "would copy $name -> $target/$name"
      continue
    fi
    # The whole folder, not just SKILL.md: a skill may ship references/,
    # scripts/ or assets/ beside it, and half a skill is worse than none. The
    # old copy goes first so a file dropped upstream does not linger here.
    mkdir -p "$target"
    rm -rf "${target:?}/${name:?}"
    cp -R "${dir%/}" "$target/$name"
  done
  [ "$DRY" = 1 ] || ok "skills -> $target"
}

remove_skills() {
  target="$1"
  for dir in "$SRC"/skills/*/; do
    name=$(basename "$dir")
    [ -d "$target/$name" ] || continue
    if [ "$DRY" = 1 ]; then skip "would remove $target/$name"; continue; fi
    rm -rf "${target:?}/${name:?}"
  done
  # An empty skills directory is this package's litter if nothing else is in
  # it. rmdir refuses when the user has skills of their own there.
  [ "$DRY" = 1 ] || rmdir "$target" 2>/dev/null || true
  [ "$DRY" = 1 ] || ok "skills removed from $target"
}

# --- rules -------------------------------------------------------------------
# The block sits between markers. A file that already has one gets it replaced
# where it stands, so anything the user wrote below it stays below it; a file
# without one gets it appended at the end.
#
# A start marker with no matching end marker is not a block. It is a damaged
# file, or a user quoting these markers in their own prose. Treating it as a
# block deleted everything from that line to the end of the file, so now it is
# reported and nothing is written.
markers_balanced() {
  awk -v s="$MARK_START" -v e="$MARK_END" '
    index($0, s) { if (open) { bad = 1 }; open = 1; next }
    index($0, e) { if (!open) { bad = 1 }; open = 0; next }
    END { exit (open || bad) ? 1 : 0 }
  ' "$1"
}

unpaired() {
  warn "$1 has a reethink start marker with no matching end marker"
  warn "left untouched: pair or remove the markers by hand, then run this again"
}

install_rules() {
  file="$1"
  [ "$file" = "none" ] && { skip "no instruction file for this target"; return; }
  if [ "$DRY" = 1 ]; then
    if [ -f "$file" ] && grep -qF "$MARK_START" "$file" 2>/dev/null; then
      skip "would refresh the rules block in $file"
    else
      skip "would add a rules block to $file"
    fi
    return
  fi
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || : > "$file"
  markers_balanced "$file" || { unpaired "$file"; return; }
  blk=$(mktemp) || die "cannot create a temporary file"
  {
    printf '%s\n' "$MARK_START"
    printf '%s\n' "<!-- reethink $VERSION by ree_es97, https://github.com/masbrokemanaaja/reethink -->"
    printf '%s\n' "<!-- Edit above or below, not inside: install.sh replaces this block. -->"
    cat "$SRC/rules/routing.md"
    printf '%s\n' "$MARK_END"
  } > "$blk"
  tmp=$(mktemp) || die "cannot create a temporary file"
  if grep -qF "$MARK_START" "$file" 2>/dev/null; then
    # The new block goes where the first one was. A second block, which only
    # exists if someone pasted one or an old version appended one, is dropped
    # rather than left behind to compete with it.
    awk -v s="$MARK_START" -v e="$MARK_END" -v blk="$blk" '
      index($0, s) {
        skipping = 1
        if (!done) {
          while ((getline line < blk) > 0) print line
          close(blk)
          done = 1
        }
        next
      }
      skipping { if (index($0, e)) { skipping = 0 }; next }
      { print }
    ' "$file" > "$tmp"
  else
    # Drop trailing blank lines so repeated installs do not grow the file,
    # while keeping every blank line inside the user's own text exactly as it
    # was written. The lines are held whole, not counted, because a line of
    # spaces is blank for this purpose but is still the user's bytes.
    awk '
      NF { for (i = 1; i <= held; i++) print buf[i]; held = 0; print; next }
      { buf[++held] = $0 }
    ' "$file" > "$tmp"
    if [ -s "$tmp" ]; then printf '\n' >> "$tmp"; fi
    cat "$blk" >> "$tmp"
  fi
  # Written with cat rather than mv on purpose: an instruction file is often a
  # symlink into a dotfiles repository, and mv would replace the link with a
  # plain file. The cost is that the write is not atomic, so the assembled copy
  # is checked before the real file is touched at all.
  if ! grep -qF "$MARK_END" "$tmp"; then
    warn "assembled rules block looks wrong; $file left untouched"
    rm -f "$tmp" "$blk"
    return
  fi
  cat "$tmp" > "$file"
  rm -f "$tmp" "$blk"
  ok "rules -> $file"
}

remove_rules() {
  file="$1"
  [ "$file" = "none" ] && return
  [ -f "$file" ] || { skip "no $file"; return; }
  grep -qF "$MARK_START" "$file" 2>/dev/null || { skip "no reethink block in $file"; return; }
  if [ "$DRY" = 1 ]; then skip "would remove the rules block from $file"; return; fi
  markers_balanced "$file" || { unpaired "$file"; return; }
  tmp=$(mktemp)
  # The one blank line this package put between the user's text and the block
  # goes out with the block. Blank lines are held rather than printed as they
  # arrive so the last of them can be dropped when the block turns out to be
  # next. A line of spaces is the user's, not a spacer, and is never held.
  awk -v s="$MARK_START" -v e="$MARK_END" '
    function flush(drop) { for (i = 1; i <= held - drop; i++) print buf[i]; held = 0 }
    index($0, s) { flush(1); skipping = 1; next }
    skipping { if (index($0, e)) { skipping = 0 }; next }
    $0 == "" { buf[++held] = $0; next }
    { flush(0); print }
    END { flush(0) }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
  # If the block was the whole file, this package created it; leaving an empty
  # file behind would be litter. A file the user wrote keeps its own text and
  # so is never empty here.
  [ -s "$file" ] || rm -f "$file"
  ok "rules removed from $file"
}

# --- hooks -------------------------------------------------------------------
# JSON is merged by python3, never rewritten wholesale: an agent's settings
# file holds far more than this package's entry.
HOOK_DIR="$HOME/.reethink"

cleanup_hook_dir() {
  # The scripts go; the log stays, because it is the record of what ran and it
  # is the user's to read or delete. hook-state.json is from a version that
  # kept state between runs; the current hook writes none, so this only clears
  # what an older install left behind.
  rm -f "$HOOK_DIR/reethink_grounding.py" "$HOOK_DIR/reethink-grounding.sh" \
        "$HOOK_DIR/hook-state.json"
  rmdir "$HOOK_DIR" 2>/dev/null || true
}

install_hook() {
  style="$1"
  [ "$style" = "none" ] && { skip "no hook support in this agent"; return; }
  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not found, skipping the hook (skills and rules still work)"
    return
  fi
  if [ "$DRY" = 1 ]; then skip "would install the $style hook"; return; fi
  mkdir -p "$HOOK_DIR"
  cp "$SRC/hooks/reethink_grounding.py" "$HOOK_DIR/reethink_grounding.py"
  cp "$SRC/hooks/reethink-grounding.sh" "$HOOK_DIR/reethink-grounding.sh"
  chmod +x "$HOOK_DIR/reethink_grounding.py" "$HOOK_DIR/reethink-grounding.sh"
  python3 "$SRC/hooks/wire_hook.py" install "$style" "$HOOK_DIR/reethink-grounding.sh" || {
    warn "could not wire the $style hook"
    return
  }
  ok "hook -> $style"
  # Codex has recorded trust against a hook's hash and skipped anything new
  # until approved, with no message when it does. Measured on 0.147.0 it did
  # exactly that; measured on 0.154.0 the same entry ran with no approval at
  # all. Which of those a given install gets is not worth guessing at, so the
  # line says how to check rather than what will happen.
  if [ "$style" = "codex" ]; then
    warn "Codex may hold a new hook for review: if the reminder does not arrive, run /hooks in Codex and approve reethink"
  fi
}

remove_hook() {
  style="$1"
  [ "$style" = "none" ] && return
  command -v python3 >/dev/null 2>&1 || return
  if [ "$DRY" = 1 ]; then skip "would remove the $style hook"; return; fi
  if python3 "$SRC/hooks/wire_hook.py" uninstall "$style" ""; then
    ok "hook removed from $style"
  fi
}

# --- main --------------------------------------------------------------------
resolve_source

say ""
say "${BOLD}reethink $VERSION${OFF}  ${DIM}grounding skills and a hook for AI coding agents${OFF}"
say "${DIM}by ree_es97, https://reetech.web.id${OFF}"
say ""

printf '%s\n' "$AGENTS" | while IFS= read -r record; do
  [ -n "$record" ] || continue
  id=$(field "$record" 1)
  name=$(field "$record" 2)
  root=$(field "$record" 3)
  skills=$(field "$record" 4)
  rules=$(field "$record" 5)
  style=$(field "$record" 6)

  [ -n "$ONLY_AGENT" ] && [ "$ONLY_AGENT" != "$id" ] && continue

  # A path, not always a directory: Gemini CLI is proved by a settings file,
  # because the directory around it belongs to Antigravity as well.
  if [ ! -e "$root" ]; then
    say "${DIM}$name${OFF} ${DIM}(not installed, skipped)${OFF}"
    continue
  fi

  say "${BOLD}$name${OFF} ${DIM}$root${OFF}"
  case "$ACTION" in
    list)
      installed=0
      total=0
      for dir in "$SRC"/skills/*/; do
        total=$((total + 1))
        [ -d "$skills/$(basename "$dir")" ] && installed=$((installed + 1))
      done
      say "  skills installed: $installed of $total"
      if [ "$rules" = "none" ]; then
        say "  rules block: not applicable"
      elif [ -f "$rules" ] && grep -qF "$MARK_START" "$rules" 2>/dev/null; then
        say "  rules block: present in $rules"
      else
        say "  rules block: absent"
      fi
      say "  hook support: $style"
      ;;
    install)
      install_skills "$skills"
      if [ "$SKILLS_ONLY" = 0 ]; then
        install_rules "$rules"
        install_hook "$style"
      fi
      ;;
    uninstall)
      remove_skills "$skills"
      remove_rules "$rules"
      remove_hook "$style"
      ;;
  esac
  say ""
done

# The loop runs in a subshell, so detection is re-checked here for the summary,
# scoped the same way the run was: under --agent, only that agent counts.
for record_id in claude-code antigravity codex gemini-cli agents-dir cursor; do
  if [ -n "$ONLY_AGENT" ] && [ "$ONLY_AGENT" != "$record_id" ]; then
    continue
  fi
  case "$record_id" in
    claude-code) root="$HOME/.claude" ;;
    antigravity) root="$HOME/.gemini/config" ;;
    codex) root="$HOME/.codex" ;;
    gemini-cli) root="$HOME/.gemini/settings.json" ;;
    agents-dir) root="$HOME/.agents" ;;
    cursor) root="$HOME/.cursor" ;;
  esac
  if [ -e "$root" ]; then detected_any=1; fi
done

if [ "$detected_any" = 0 ] && [ "$ACTION" = "uninstall" ]; then
  # No agent directory left to clean, but this package's own files can still be
  # here: the agent may have been removed after reethink was installed.
  cleanup_hook_dir
  say "${DIM}Removed.${OFF}"
  say ""
  exit 0
fi

if [ "$detected_any" = 0 ]; then
  warn "no supported agent found on this machine"
  say ""
  say "  reethink skills follow the Agent Skills open standard, so they work in"
  say "  any compatible tool. Copy skills/* into your agent's skills directory"
  say "  and paste rules/routing.md into its instruction file. See the README."
  say ""
  exit 0
fi

case "$ACTION" in
  install)
    say "${DIM}Restart your agent to pick up the new skills.${OFF}"
    say "${DIM}Hook activity is logged to ~/.reethink/hooks.log${OFF}"
    say "${DIM}Undo any time with: sh uninstall.sh${OFF}"
    ;;
  uninstall)
    # The scripts in ~/.reethink are shared by every agent, so they only go
    # once no agent's config still points at them. Uninstalling one agent used
    # to delete them out from under the others, which left the rest erroring
    # on every turn against a path that was no longer there.
    if [ -n "$ONLY_AGENT" ] && command -v python3 >/dev/null 2>&1 \
       && python3 "$SRC/hooks/wire_hook.py" wired; then
      skip "another agent still uses $HOOK_DIR, so its scripts stay"
    else
      cleanup_hook_dir
    fi
    if [ -f "$HOOK_DIR/hooks.log" ]; then
      say "${DIM}Removed. The hook log is still at ~/.reethink/hooks.log; delete it if you want it gone.${OFF}"
    else
      say "${DIM}Removed.${OFF}"
    fi
    ;;
esac
say ""

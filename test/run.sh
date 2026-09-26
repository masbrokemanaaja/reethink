#!/bin/sh
# reethink test suite.
#
# Everything runs against a temporary HOME, so it never reads or writes the
# real configuration on this machine. The point is to check the claims the
# README makes, not to exercise every line: the skills parse as the spec
# describes and are routed, the hook answers both host contracts and survives
# bad input, the rules block is idempotent and leaves the user's own text where
# and as it was written, a damaged marker pair is refused rather than acted on,
# a bad --agent name fails loudly, and an uninstall gives the files back byte
# for byte.
#
# Every check here exists because something went wrong once. Adding a fix
# without the check that fails without it is how it comes back.
#
#   sh test/run.sh
#
# reethink, by ree_es97 (https://reetech.web.id)
# MIT licensed. https://github.com/masbrokemanaaja/reethink

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
PASS=0
FAIL=0

GREEN=""; RED=""; DIM=""; OFF=""
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  GREEN=$(printf '\033[32m'); RED=$(printf '\033[31m')
  DIM=$(printf '\033[2m'); OFF=$(printf '\033[0m')
fi

pass() { PASS=$((PASS + 1)); printf '  %sok%s   %s\n' "$GREEN" "$OFF" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  %sFAIL%s %s\n' "$RED" "$OFF" "$1"; }
check() { if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected $1, got $2)"; fi; }
group() { printf '\n%s%s%s\n' "$DIM" "$1" "$OFF"; }

command -v python3 >/dev/null 2>&1 || { echo "python3 is required to run the tests" >&2; exit 2; }

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
HOME_DIR="$SANDBOX/home"
mkdir -p "$HOME_DIR/.claude" "$HOME_DIR/.gemini/config" "$HOME_DIR/.codex"

run_install() { env HOME="$HOME_DIR" sh "$ROOT/install.sh" "$@" >/dev/null 2>&1; }
hook() { env HOME="$HOME_DIR" python3 "$ROOT/hooks/reethink_grounding.py"; }

# --- the skills parse the way the spec describes -----------------------------
group "skills"
if python3 - "$ROOT" <<'PY'
import os, re, sys
_c = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
G = "\033[32m" if _c else ""
R = "\033[31m" if _c else ""
O = "\033[0m" if _c else ""
root = sys.argv[1]
skills = os.path.join(root, "skills")
problems = []
names = sorted(os.listdir(skills))
for name in names:
    path = os.path.join(skills, name, "SKILL.md")
    if not os.path.isfile(path):
        problems.append(f"{name}: no SKILL.md")
        continue
    text = open(path, encoding="utf-8").read()
    if not text.startswith("---\n"):
        problems.append(f"{name}: no frontmatter")
        continue
    front = text.split("---\n", 2)[1]
    got = dict(re.findall(r"^([a-z-]+):[ ]*(.*)$", front, re.M))
    if got.get("name") != name:
        problems.append(f"{name}: name field is {got.get('name')!r}, must match the directory")
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name) or len(name) > 64:
        problems.append(f"{name}: not a valid skill name")
    desc = got.get("description", "")
    if not desc:
        problems.append(f"{name}: no description")
    elif len(desc) > 1024:
        problems.append(f"{name}: description is {len(desc)} chars, the limit is 1024")
    body = text.split("---\n", 2)[2]
    if len(body.splitlines()) > 500:
        problems.append(f"{name}: body is over 500 lines")
for p in problems:
    print(f"  {R}FAIL{O}", p)
if not problems:
    print(f"  {G}ok{O}   {len(names)} skills valid against the Agent Skills spec")
sys.exit(1 if problems else 0)
PY
then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi

# --- every skill is actually routed ------------------------------------------
# The installer picks up skill folders on its own, but the routing block and
# the hook message name them one by one. This is the check that catches a new
# skill nobody told the agent about.
if python3 - "$ROOT" <<'PY'
import os, sys
_c = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
G = "\033[32m" if _c else ""
R = "\033[31m" if _c else ""
O = "\033[0m" if _c else ""
root = sys.argv[1]
routing = open(os.path.join(root, "rules", "routing.md"), encoding="utf-8").read()
hook = open(os.path.join(root, "hooks", "reethink_grounding.py"), encoding="utf-8").read()
missing = []
for name in sorted(os.listdir(os.path.join(root, "skills"))):
    if name not in routing:
        missing.append(f"{name} is not named in rules/routing.md")
    if name not in hook:
        missing.append(f"{name} is not named in the hook message")
for m in missing:
    print(f"  {R}FAIL{O}", m)
if not missing:
    print(f"  {G}ok{O}   every skill is named in the routing block and the hook")
sys.exit(1 if missing else 0)
PY
then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi

# --- the hook speaks both dialects -------------------------------------------
group "hook"
out=$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"t"}' | hook)
case "$out" in
  *additionalContext*) pass "Claude Code UserPromptSubmit gets additionalContext" ;;
  *) fail "Claude Code UserPromptSubmit: $out" ;;
esac

out=$(printf '{"hook_event_name":"PreToolUse","session_id":"t"}' | hook)
check '{}' "$out" "a different Claude Code event injects nothing"

first=$(printf '{"invocationNum":0,"conversationId":"c"}' | hook)
second=$(printf '{"invocationNum":1,"conversationId":"c"}' | hook)
third=$(printf '{"invocationNum":2,"conversationId":"c"}' | hook)
fourth=$(printf '{"invocationNum":0,"conversationId":"c"}' | hook)
case "$first" in *ephemeralMessage*) pass "Antigravity injects on the first call of a turn" ;;
  *) fail "Antigravity first call: $first" ;; esac
check '{}' "$second" "Antigravity stays quiet on later calls"
check '{}' "$third" "Antigravity stays quiet on later calls again"
case "$fourth" in *ephemeralMessage*) pass "Antigravity injects again on the next turn" ;;
  *) fail "Antigravity next turn: $fourth" ;; esac

# Antigravity documents invocationNum as 0-indexed per turn, so the rule is
# that comparison and nothing is remembered between runs. A hook wired in the
# middle of a turn therefore cannot land on the wrong call, and cannot learn a
# numbering it would then keep getting wrong.
mid=$(printf '{"invocationNum":2,"conversationId":"e"}' | hook)
check '{}' "$mid" "a hook wired mid-turn stays quiet until the next turn starts"
after=$(printf '{"invocationNum":0,"conversationId":"f"}' | hook)
case "$after" in *ephemeralMessage*) pass "and injects on the first call of that next turn" ;;
  *) fail "the call after a mid-turn start: $after" ;; esac
check '{}' "$(printf '{"invocationNum":"nonsense"}' | hook)" \
  "a counter that is not a number injects nothing"
if [ -e "$HOME_DIR/.reethink/hook-state.json" ]; then
  fail "the hook writes a state file that can drift out of step"
else
  pass "the hook keeps no state between runs, so there is nothing to drift"
fi

check '{}' "$(printf 'not json at all' | hook)" "garbage input injects nothing"
check '{}' "$(printf '' | hook)" "empty input injects nothing"
check '{}' "$(printf '"a bare string"' | hook)" "a non-object payload injects nothing"
check '{}' "$(printf '{"something":"else"}' | hook)" "an unknown host injects nothing"

# --- the rules block leaves the user's own text alone ------------------------
group "rules"
rules="$HOME_DIR/.claude/CLAUDE.md"
cat > "$rules" <<'MD'
# My own notes

Some prose with a blank line after it.

## A heading

    an indented code block
    that must survive

Closing line.
MD
cp "$rules" "$SANDBOX/rules.before"

run_install --agent claude-code
run_install --agent claude-code
run_install --agent claude-code

blocks=$(grep -c 'reethink:start' "$rules" || true)
check "1" "$blocks" "three installs leave exactly one rules block"

if python3 - "$rules" "$SANDBOX/rules.before" <<'PY'
import os, sys
_c = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
G = "\033[32m" if _c else ""
R = "\033[31m" if _c else ""
O = "\033[0m" if _c else ""
after = open(sys.argv[1], encoding="utf-8").read()
before = open(sys.argv[2], encoding="utf-8").read()
head = after.split("<!-- reethink:start -->")[0]
same = head.rstrip("\n") == before.rstrip("\n")
print(f"  {G}ok{O}   the user's own text is byte for byte unchanged" if same
      else f"  {R}FAIL{O} the user's own text changed")
sys.exit(0 if same else 1)
PY
then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi

skills_count=0
skills_total=0
for dir in "$ROOT"/skills/*/; do
  skills_total=$((skills_total + 1))
  [ -f "$HOME_DIR/.claude/skills/$(basename "$dir")/SKILL.md" ] && skills_count=$((skills_count + 1))
done
check "$skills_total" "$skills_count" "every skill lands in the agent's skills directory"

# --- a settings file comes back identical ------------------------------------
group "settings merge"
settings="$HOME_DIR/.claude/settings.json"
cat > "$settings" <<'JSON'
{
  "model": "opus",
  "permissions": {
    "allow": ["Bash(git *)"]
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "~/my-own-logger.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [{ "type": "command", "command": "prettier" }]
      }
    ]
  }
}
JSON
cp "$settings" "$SANDBOX/settings.before"

run_install --agent claude-code
run_install --agent claude-code

entries=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["hooks"]["UserPromptSubmit"]))' "$settings")
check "2" "$entries" "two installs leave the user's hook plus ours, not three"

kept=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
ok = (d.get("model") == "opus"
      and d["permissions"]["allow"] == ["Bash(git *)"]
      and d["hooks"]["PostToolUse"][0]["matcher"] == "Write")
print("yes" if ok else "no")' "$settings")
check "yes" "$kept" "the user's other settings and hooks are untouched"

# Non-ASCII in the user's own settings has to survive the round trip as
# characters. json.dump escapes it by default, which leaves every value equal
# and every line different, so a parsed comparison never catches it.
utf8="$SANDBOX/home7"
mkdir -p "$utf8/.claude"
# The characters are written as Python escapes so this file stays ASCII and
# the repository's own no-em-dash rule can be checked with a plain grep.
python3 -c '
import json, sys
json.dump({"permissions": {"deny": ["catatan \u2014 jangan hapus", "caf\u00e9"]}},
          open(sys.argv[1], "w", encoding="utf-8"), indent=2, ensure_ascii=False)' \
  "$utf8/.claude/settings.json"
env HOME="$utf8" sh "$ROOT/install.sh" --agent claude-code >/dev/null 2>&1
if grep -q '\\u' "$utf8/.claude/settings.json"; then
  fail "non-ASCII in a settings file came back as a backslash-u escape"
else
  pass "non-ASCII in a settings file stays a character, not a backslash-u escape"
fi

run_install --uninstall
identical=$(python3 -c '
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
print("yes" if a == b else "no")' "$settings" "$SANDBOX/settings.before")
check "yes" "$identical" "uninstall gives back the settings file it found"

left=0
for dir in "$ROOT"/skills/*/; do
  [ -d "$HOME_DIR/.claude/skills/$(basename "$dir")" ] && left=$((left + 1))
done
check "0" "$left" "uninstall removes the skills it installed"
if [ -d "$HOME_DIR/.claude/skills" ]; then
  fail "uninstall left an empty skills directory behind"
else
  pass "uninstall leaves no empty skills directory behind"
fi
check "0" "$(grep -c 'reethink:start' "$rules" || true)" "uninstall removes the rules block"

if [ -e "$HOME_DIR/.reethink/reethink-grounding.sh" ]; then
  fail "uninstall left the hook script behind"
else
  pass "uninstall removes the hook script"
fi
if [ -f "$HOME_DIR/.reethink/hooks.log" ]; then
  pass "uninstall keeps the log, which is the user's to delete"
else
  fail "uninstall deleted the log"
fi

# --- a config we cannot parse is reported, never overwritten -----------------
group "safety"
printf '{ this is not json' > "$settings"
cp "$settings" "$SANDBOX/broken.before"
run_install --agent claude-code || true
if cmp -s "$settings" "$SANDBOX/broken.before"; then
  pass "a settings file that is not valid JSON is left untouched"
else
  fail "a settings file that is not valid JSON was overwritten"
fi

# Valid JSON, but not the shape this package expects. Same rule, and the user
# gets one sentence rather than a Python stack trace.
printf '{"hooks":{"UserPromptSubmit":"my-own-script.sh"}}' > "$settings"
cp "$settings" "$SANDBOX/shape.before"
shapeout=$(env HOME="$HOME_DIR" sh "$ROOT/install.sh" --agent claude-code 2>&1 || true)
case "$shapeout" in
  *Traceback*) fail "an unexpected settings shape prints a Python traceback" ;;
  *"unexpected shape"*) pass "an unexpected settings shape is reported in one sentence" ;;
  *) fail "an unexpected settings shape was not reported at all" ;;
esac
if cmp -s "$settings" "$SANDBOX/shape.before"; then
  pass "a settings file of an unexpected shape is left untouched"
else
  fail "a settings file of an unexpected shape was overwritten"
fi
rm -f "$settings"

# --- an agent name that is not in the table fails loudly ---------------------
# Skipping every record and still printing "Restart your agent to pick up the
# new skills" told the user the install worked when nothing was written.
group "arguments"
home3="$SANDBOX/home3"
mkdir -p "$home3/.claude"
if env HOME="$home3" sh "$ROOT/install.sh" --agent notanagent > "$SANDBOX/argout" 2>&1; then
  fail "an unknown --agent name exits 0"
else
  case $(cat "$SANDBOX/argout") in
    *"unknown agent: notanagent"*"claude-code"*)
      pass "an unknown --agent name fails and names the ones it knows" ;;
    *) fail "an unknown --agent name failed without saying why: $(cat "$SANDBOX/argout")" ;;
  esac
fi
if env HOME="$home3" sh "$ROOT/install.sh" --agent "" >/dev/null 2>&1; then
  fail "an empty --agent name is taken as 'every agent'"
else
  pass "an empty --agent name is rejected"
fi
if [ -d "$home3/.claude/skills" ]; then
  fail "a rejected --agent run created a skills directory"
else
  pass "a rejected --agent run writes nothing"
fi

# --- two Google products in one directory ------------------------------------
# Antigravity and Antigravity IDE share ~/.gemini/config, so one row covers
# both. Gemini CLI is a third product in the same tree with its own skills
# directory, and ~/.gemini exists as soon as Antigravity does, so a settings
# file has to be what proves Gemini CLI is there.
group "gemini products"
hg="$SANDBOX/homegemini"
mkdir -p "$hg/.gemini/config"
case "$(env HOME="$hg" sh "$ROOT/install.sh" --list 2>&1)" in
  *"Gemini CLI (not installed"*) pass "Antigravity alone is not mistaken for Gemini CLI" ;;
  *) fail "Antigravity alone was detected as Gemini CLI" ;;
esac
printf '{}' > "$hg/.gemini/settings.json"
printf 'my own gemini notes\n' > "$hg/.gemini/GEMINI.md"
env HOME="$hg" sh "$ROOT/install.sh" >/dev/null 2>&1
gem=0
for dir in "$ROOT"/skills/*/; do
  [ -f "$hg/.gemini/skills/$(basename "$dir")/SKILL.md" ] && gem=$((gem + 1))
done
check "$skills_total" "$gem" "a settings file makes Gemini CLI a target of its own"
check "1" "$(grep -c 'reethink:start' "$hg/.gemini/GEMINI.md" || true)" \
  "both products write GEMINI.md and it still holds one block"
env HOME="$hg" sh "$ROOT/uninstall.sh" >/dev/null 2>&1
check "my own gemini notes" "$(cat "$hg/.gemini/GEMINI.md" 2>/dev/null)" \
  "and uninstall gives that file back with only the user's own text"

# --- the targets that are directories rather than agents ---------------------
# ~/.agents/skills is the cross-tool alias Gemini CLI, Codex and Cursor all
# document, so it is a target in its own right. It has no instruction file and
# no hook, and the installer has to skip both rather than write to "none".
group "shared skills directory"
hs="$SANDBOX/homeshared"
mkdir -p "$hs/.agents/skills/someone-elses-skill"
printf 'x\n' > "$hs/.agents/skills/someone-elses-skill/SKILL.md"
env HOME="$hs" sh "$ROOT/install.sh" --agent agents-dir >/dev/null 2>&1
shared=0
for dir in "$ROOT"/skills/*/; do
  [ -f "$hs/.agents/skills/$(basename "$dir")/SKILL.md" ] && shared=$((shared + 1))
done
check "$skills_total" "$shared" "every skill lands in ~/.agents/skills"
if [ -e "$hs/.agents/AGENTS.md" ] || [ -e "$hs/.agents/none" ]; then
  fail "a target with no instruction file had one written anyway"
else
  pass "a target with no instruction file gets no rules block and no file called none"
fi
env HOME="$hs" sh "$ROOT/uninstall.sh" >/dev/null 2>&1
if [ -f "$hs/.agents/skills/someone-elses-skill/SKILL.md" ]; then
  pass "uninstall leaves a skill this package did not install"
else
  fail "uninstall removed a skill belonging to someone else"
fi

# --- a skill is copied whole, not just its SKILL.md --------------------------
# Nothing here ships a references/ or scripts/ directory yet, so the source
# tree is copied and one is added: the check has to fail if install.sh goes
# back to copying the single file.
group "skill payload"
src2="$SANDBOX/src"
mkdir -p "$src2"
cp -R "$ROOT/skills" "$ROOT/rules" "$ROOT/hooks" "$src2/"
cp "$ROOT/install.sh" "$src2/install.sh"
mkdir -p "$src2/skills/multi-file-probe/references"
printf -- '---\nname: multi-file-probe\ndescription: probe\n---\n\nbody\n' \
  > "$src2/skills/multi-file-probe/SKILL.md"
printf 'reference text\n' > "$src2/skills/multi-file-probe/references/notes.md"
home2="$SANDBOX/home2"
mkdir -p "$home2/.claude"
env HOME="$home2" sh "$src2/install.sh" --agent claude-code >/dev/null 2>&1 || true
if [ -f "$home2/.claude/skills/multi-file-probe/references/notes.md" ]; then
  pass "a skill folder with extra files is copied whole"
else
  fail "a skill folder with extra files arrived as SKILL.md only"
fi

# --- the designer's two scripts do what the skill says they do -----------------
# senior-designer quotes a count of valid directions, promises that a seed
# reproduces a direction, that three directions sit six axes apart, and that
# every palette it offers has already passed its contrast checks. Each of
# those is a claim a reader acts on, so each is measured here rather than
# trusted. The WCAG formula is written out again below instead of imported,
# so a wrong formula in palette.py cannot grade its own homework.
group "designer scripts"
DESIGN="$ROOT/skills/senior-designer/scripts"
# No bytecode: install.sh copies a skill folder whole, so a __pycache__ left
# here by the suite would be installed into somebody's agent.
designer_check() {
  if dout=$(PYTHONDONTWRITEBYTECODE=1 python3 - "$DESIGN" "$ROOT" 2>&1); then
    pass "$1"
  else
    fail "$1: $dout"
  fi
}

designer_check "the direction count in SKILL.md and both READMEs is the one the script computes" <<'PY'
import os, subprocess, sys
scripts, root = sys.argv[1], sys.argv[2]
sys.path.insert(0, scripts)
import direction
web, mobile = direction.count_valid("web"), direction.count_valid("mobile")
skill = open(os.path.join(root, "skills/senior-designer/SKILL.md"), encoding="utf-8").read()
en = open(os.path.join(root, "README.md"), encoding="utf-8").read()
idn = open(os.path.join(root, "README-ID.md"), encoding="utf-8").read()
want = [(skill, f"{web:,}", "SKILL.md web"), (skill, f"{mobile:,}", "SKILL.md mobile"),
        (en, f"{web:,}", "README.md"), (idn, f"{web:,}".replace(",", "."), "README-ID.md")]
missing = [label for text, number, label in want if number not in text]
if missing:
    sys.exit(f"{', '.join(missing)} do not quote {web:,} (web) and {mobile:,} (mobile)")
PY

designer_check "the inclusion-exclusion count agrees with brute force on the real rules" <<'PY'
import itertools, sys
sys.path.insert(0, sys.argv[1])
import direction
# Every option a rule names, plus one it does not, keeps the brute force small
# enough to run here while still exercising every rule. The full space was
# brute-forced once, in 30.8s, and agreed with the formula to the unit.
named = {}
for pairs, _ in direction.RULES + direction.SURFACE_RULES["mobile"]:
    for axis, option in pairs:
        named.setdefault(axis, set()).add(option)
small = {}
for axis, options in direction.AXES.items():
    keep = set(named.get(axis, ()))
    keep.add(next(o for o in sorted(options) if o not in keep))
    small[axis] = {o: options[o] for o in sorted(keep)}
for surface in ("web", "mobile"):
    brute = 0
    for combo in itertools.product(*(sorted(o) for o in small.values())):
        if direction.broken_rule(dict(zip(small, combo)), surface) is None:
            brute += 1
    formula = direction.count_valid(surface, small)
    if brute != formula:
        sys.exit(f"{surface}: brute force {brute}, formula {formula}")
PY

designer_check "a direction seed reproduces the same direction, fonts and all" <<'PY'
import json, subprocess, sys
script = sys.argv[1] + "/direction.py"
run = lambda *a: subprocess.run([sys.executable, script, *a], capture_output=True, text=True, check=True).stdout
if run("show", "48213", "--json") != run("show", "48213", "--json"):
    sys.exit("show 48213 gave two different answers")
if run("roll", "--seed", "5", "--json") != run("roll", "--seed", "5", "--json"):
    sys.exit("roll --seed 5 gave two different answers")
one = json.loads(run("roll", "--seed", "5", "--json"))[0]
if json.loads(run("show", str(one["seed"]), "--json")) != one:
    sys.exit("a rolled direction and show of its seed differ")
PY

designer_check "three rolled directions sit six axes apart and break no rule" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import direction
# Written out here rather than read from RULES, so a rule dropped from the
# script is caught instead of agreed with.
never = [({"composition": "index", "density": "airy"}, "web"),
         ({"composition": "poster", "density": "dense"}, "web"),
         ({"type": "single-face", "hierarchy": "weight"}, "web"),
         ({"icons": "none"}, "mobile")]
for surface in ("web", "mobile"):
    for master in range(60):
        found = direction.roll(3, surface, master)
        if len(found) != 3:
            sys.exit(f"{surface} master {master}: {len(found)} directions")
        for i, a in enumerate(found):
            for b in found[i + 1:]:
                if direction.distance(a, b) < 6:
                    sys.exit(f"{surface} master {master}: seeds {a['seed']} and {b['seed']} are too close")
            for combo, where in never:
                applies = where == "web" or where == surface
                if applies and all(a["axes"][k] == v for k, v in combo.items()):
                    sys.exit(f"{surface} seed {a['seed']} rolled {combo}")
PY

designer_check "--avoid keeps a new direction six axes from the one already used" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import direction
used = direction.build(48213, "web")
for master in range(40):
    new = direction.roll(1, "web", master, avoid=[48213])[0]
    if direction.distance(new, used) < 6:
        sys.exit(f"master {master}: seed {new['seed']} is {direction.distance(new, used)} axes from 48213")
PY

designer_check "no overused default font is ever picked" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import direction
banned = {"Inter", "Roboto", "Poppins", "Montserrat", "Open Sans", "Lato",
          "Space Grotesk", "Playfair Display", "Oswald", "Bebas Neue"}
pooled = {f for display, text in direction.FONTS.values() for f in display + (text or ())}
if pooled & banned:
    sys.exit(f"pooled anyway: {sorted(pooled & banned)}")
if set(direction.FONTS) != set(direction.AXES["type"]):
    sys.exit("a type strategy has no font pool, or a pool has no strategy")
PY

designer_check "palette.py measures contrast and OKLCH the way WCAG and Oklab define them" <<'PY'
import subprocess, sys
sys.path.insert(0, sys.argv[1])
import palette
run = lambda *a: subprocess.run([sys.executable, sys.argv[1] + "/palette.py", *a],
                                capture_output=True, text=True, check=True).stdout.split()[0]
# 4.54 is the ratio usually quoted for #767676 on white; #777777 is 4.478,
# which has to show as 4.47 because rounding it to 4.48 would still pass and
# rounding a 4.499 to 4.50 would not be allowed to.
got = (run("contrast", "#767676", "#FFFFFF"), run("contrast", "#777777", "#FFFFFF"),
       run("contrast", "#000", "#fff"))
if got != ("4.54", "4.47", "21.00"):
    sys.exit(f"contrast gave {got}")
L, C, h = palette.hex_to_oklch("#FF0000")
if (round(L, 3), round(C, 3), round(h, 1)) != (0.628, 0.258, 29.2):
    sys.exit(f"#FF0000 is oklch({L:.4f} {C:.4f} {h:.2f}), expected 0.628 0.258 29.2")
for hx in ("#1B1B1B", "#F4EFE6", "#C8553D", "#0B7A75", "#FFFFFF"):
    if palette.oklch_to_hex(*palette.hex_to_oklch(hx)) != hx:
        sys.exit(f"{hx} does not survive a round trip through OKLCH")
PY

designer_check "every suggested palette passes the ratios it prints, measured independently" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import palette

def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def ratio(a, b):
    lum = lambda h: sum(w * lin(int(h[i:i + 2], 16) / 255) for w, i in ((0.2126, 1), (0.7152, 3), (0.0722, 5)))
    x, y = sorted((lum(a), lum(b)), reverse=True)
    return (x + 0.05) / (y + 0.05)

need = {("ink", "paper"): 7.0, ("ink", "surface"): 4.5, ("muted", "paper"): 4.5,
        ("accent-text", "paper"): 4.5, ("on-accent", "accent"): 4.5,
        ("accent", "paper"): 3.0, ("control-border", "paper"): 3.0,
        ("accent-2", "paper"): 3.0}
for mode in ("light", "dark"):
    for master in range(15):
        found = palette.suggest(3, mode, master)
        if len(found) != 3:
            sys.exit(f"{mode} master {master}: {len(found)} palettes")
        hues = []
        for p in found:
            r = p["roles"]
            for (fg, bg), n in need.items():
                if fg in r and ratio(r[fg], r[bg]) < n:
                    sys.exit(f"{mode} seed {p['seed']}: {fg} on {bg} is {ratio(r[fg], r[bg]):.3f}, needs {n}")
            base = float(p["base"].split("(")[1].rstrip(")"))
            if 268 <= base <= 312:
                sys.exit(f"{mode} seed {p['seed']}: base hue {base} is in the indigo to violet band")
            hues.append(base)
        for i, a in enumerate(hues):
            for b in hues[i + 1:]:
                if min(abs(a - b) % 360, 360 - abs(a - b) % 360) < 60:
                    sys.exit(f"{mode} master {master}: base hues {a:.0f} and {b:.0f} are too close")
brand = palette.suggest(3, "light", 1, brand="#C8553D")
if not brand or any(p["roles"]["accent"] != "#C8553D" for p in brand):
    sys.exit("--brand did not keep the brand color exactly")
PY

designer_check "tokens.py writes the chosen seeds down and emits tokens that remove the defaults" <<'PY'
import json, os, subprocess, sys, tempfile
scripts = sys.argv[1]
run = lambda *a: subprocess.run([sys.executable, os.path.join(scripts, "tokens.py"), *a],
                                capture_output=True, text=True, check=True).stdout
with tempfile.TemporaryDirectory() as tmp:
    spec_path = os.path.join(tmp, "design-direction.json")
    run("spec", "--direction", "822532", "--palette", "914858", "--mode", "dark",
        "--brand", "#22d3ee", "--scheme", "triadic", "--out", spec_path)
    spec = json.load(open(spec_path))
    if (spec["fonts"]["display"], spec["fonts"]["text"], spec["fonts"]["source"]) != (
            "Fragment Mono", "Red Hat Text", "rolled"):
        sys.exit(f"spec recorded fonts {spec['fonts']}")
    if spec["palette"]["roles"]["accent"] != "#22D3EE" or len(spec["palette"]["roles"]) != 10:
        sys.exit(f"spec recorded roles {spec['palette']['roles']}")
    block = run("emit", spec_path)
    for want in ["--color-*: initial;", "--font-*: initial;", "--radius-container: 20px;",
                 '--font-display: "Fragment Mono", ui-monospace'] + [
                 f"--color-{r}: {h};" for r, h in spec["palette"]["roles"].items()]:
        if want not in block:
            sys.exit(f"the Tailwind block lacks {want}")
    run("spec", "--direction", "822532", "--palette", "914858", "--mode", "dark",
        "--brand", "#22d3ee", "--scheme", "triadic", "--brand-fonts", "Space Grotesk,Inter",
        "--out", spec_path)
    if json.load(open(spec_path))["fonts"]["source"] != "brand":
        sys.exit("--brand-fonts did not record the fonts as the brand's")
PY

designer_check "verify.py passes code and copy that follow the spec, and names each planted tell" <<'PY'
import json, os, subprocess, sys, tempfile
scripts = sys.argv[1]
py = lambda name, *a: subprocess.run([sys.executable, os.path.join(scripts, name), *a],
                                     capture_output=True, text=True)
with tempfile.TemporaryDirectory() as tmp:
    spec = os.path.join(tmp, "design-direction.json")
    py("tokens.py", "spec", "--direction", "822532", "--palette", "914858", "--mode", "dark",
       "--brand", "#22d3ee", "--scheme", "triadic", "--out", spec)
    tree = {n: os.path.join(tmp, n) for n in ("clean", "clean-site", "dirty", "dirty-site")}
    for d in tree.values():
        os.makedirs(os.path.join(d, "projects"))
    write = lambda d, name, text: open(os.path.join(tree[d], name), "w").write(text)
    write("clean", "global.css", '@import "tailwindcss";\n' + py("tokens.py", "emit", spec).stdout + "\n")
    write("clean", "Hero.tsx",
          '<a href="#add" className="bg-paper text-ink font-display rounded-container '
          'border border-rule">x</a>\n'
          '<span className="rounded-full bg-accent text-on-accent" style={{boxShadow: '
          '"0 8px 24px rgba(0,0,0,0.4)"}} />\n')
    write("clean-site", "index.html",
          '<html><head><link rel="stylesheet" href="/projects/site.css"></head><body>'
          '<h1>Rama</h1><p>3+ <span>years</span> of shipping</p>'
          '<a href="/projects/">projects</a></body></html>\n')
    write("clean-site", "projects/index.html", "<p>GEMS</p>\n")
    write("clean-site", "projects/site.css", "")
    claims = os.path.join(tmp, "design-claims.json")
    json.dump({"claims": [{"text": "3+ years", "source": "user, this conversation"}]}, open(claims, "w"))
    out = py("verify.py", spec, tree["clean"], "--site", tree["clean-site"], "--claims", claims)
    if out.returncode != 0:
        sys.exit("clean fixture failed:\n" + out.stdout)
    # One line per check, each copied from what a real redesign shipped.
    write("dirty", "global.css", "@theme {\n  --font-sans: 'Inter', system-ui, sans-serif;\n}\n")
    write("dirty", "Page.tsx", "\n".join([
        '<p className="text-cyan-400">a</p>',
        '<div className="bg-[#131619]">b</div>',
        '<button className="shadow-[0_0_20px_rgba(34,211,238,0.25)]">c</button>',
        '<h1 className="bg-clip-text">d</h1>',
        '<nav className="backdrop-blur-md">e</nav>',
        '<div className="rounded-xl">f</div>',
        '<div style={{backgroundImage: "url(https://grainy-gradients.vercel.app/noise.svg)"}} />',
    ]) + "\n")
    write("dirty-site", "index.html",
          "<p>100%</p><div>AUDIT TOKEN</div><p>[2021 - 2024] Freelance</p>"
          '<a href="/about/">about</a><footer>[SPEC: DIR-822532 // PAL-914858 // WCAG-2.2-AA]</footer>\n')
    out = py("verify.py", spec, tree["dirty"], "--site", tree["dirty-site"], "--json")
    report = json.loads(out.stdout)
    failed = {c["name"] for c in report["checks"] if c["count"] and c["level"] == "fail"}
    warned = {c["name"] for c in report["checks"] if c["count"] and c["level"] == "warn"}
    want = {"fonts", "overused fonts", "palette", "default colors", "glow", "gradient text",
            "glass", "radius", "claims", "links", "process leak"}
    if out.returncode != 1 or failed != want or warned != {"hotlinks", "process words"}:
        sys.exit(f"exit {out.returncode}, failed {sorted(failed)}, warned {sorted(warned)}")
    # And each planted fact is named on its own, so losing one pattern cannot
    # hide behind another that still fails the same check.
    hits = {c["name"]: " | ".join(h["text"] for h in c["hits"]) for c in report["checks"]}
    for check, needle in [("claims", "100%"), ("claims", "2021 - 2024"), ("links", "/about/"),
                          ("process leak", "822532"), ("process leak", "914858")]:
        if needle not in hits[check]:
            sys.exit(f"{check} did not name {needle}: {hits[check]}")
    # Without the build the words were never read, which is not a pass.
    out = py("verify.py", spec, tree["clean"], "--json")
    names = {c["name"] for c in json.loads(out.stdout)["checks"] if c["count"]}
    if out.returncode != 1 or names != {"claims"}:
        sys.exit(f"without --site: exit {out.returncode}, failing {sorted(names)}")
    json.dump({"claims": [{"text": "3+ years", "source": ""}]}, open(claims, "w"))
    out = py("verify.py", spec, tree["clean"], "--site", tree["clean-site"], "--claims", claims)
    if out.returncode != 1 or "no source given" not in out.stdout:
        sys.exit("a claim with no source passed")
PY

designer_check "verify.py --links fails a dead link, and only warns on a site that refuses scripts" <<'PY'
import http.server, json, os, subprocess, sys, tempfile, threading
scripts = sys.argv[1]

class Handler(http.server.BaseHTTPRequestHandler):
    CODES = {"/ok": 200, "/gone": 404, "/refused": 999}
    def _answer(self):
        self.send_response(self.CODES.get(self.path, 404))
        self.end_headers()
    do_HEAD = do_GET = _answer
    def log_message(self, *a):
        pass

server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{server.server_port}"
try:
    with tempfile.TemporaryDirectory() as tmp:
        spec = os.path.join(tmp, "design-direction.json")
        subprocess.run([sys.executable, os.path.join(scripts, "tokens.py"), "spec", "--direction", "822532",
                        "--palette", "914858", "--mode", "dark", "--brand", "#22d3ee", "--scheme",
                        "triadic", "--out", spec], check=True, capture_output=True)
        src, site = os.path.join(tmp, "src"), os.path.join(tmp, "site")
        os.makedirs(src); os.makedirs(site)
        open(os.path.join(site, "index.html"), "w").write(
            f'<a href="{base}/ok">ok</a><a href="{base}/refused">in</a>'
            f'<code>curl -sL {base}/gone</code>\n')
        out = subprocess.run([sys.executable, os.path.join(scripts, "verify.py"), spec, src,
                              "--site", site, "--links", "--json"], capture_output=True, text=True)
        checks = {c["name"]: [h["text"] for h in c["hits"]] for c in json.loads(out.stdout)["checks"]}
        if checks["links"] != [f"404: {base}/gone"] or checks["links refused"] != [f"999: {base}/refused"]:
            sys.exit(f"links {checks['links']}, refused {checks['links refused']}")
finally:
    server.shutdown()
PY

# --- piped from curl, the cwd is not the source ------------------------------
# Read from stdin, $0 is "sh" and dirname "sh" is ".", so a stray skills/ in
# the working directory used to be installed instead of the real package. With
# curl removed from PATH the correct behaviour is a clean failure.
group "piped source"
mkdir -p "$SANDBOX/stray/skills/pretend" "$SANDBOX/nopath"
printf -- '---\nname: pretend\ndescription: x\n---\n' \
  > "$SANDBOX/stray/skills/pretend/SKILL.md"
if piped=$(cd "$SANDBOX/stray" && env HOME="$HOME_DIR" PATH="$SANDBOX/nopath" \
  /bin/sh -s -- --list < "$ROOT/install.sh" 2>&1); then
  :
fi
case "$piped" in
  *"no local copy found"*) pass "piped from stdin, a stray skills/ in the cwd is not the source" ;;
  *) fail "piped from stdin, the source resolved elsewhere: $piped" ;;
esac

# --- the user's own text keeps its bytes and its place -----------------------
group "rules placement"
h5="$SANDBOX/home5"
mkdir -p "$h5/.claude"
r5="$h5/.claude/CLAUDE.md"
printf 'top line\n   \nmiddle line\n' > "$r5"
env HOME="$h5" sh "$ROOT/install.sh" --agent claude-code >/dev/null 2>&1
printf 'bottom line\n' >> "$r5"
cp "$r5" "$SANDBOX/r5.before"
env HOME="$h5" sh "$ROOT/install.sh" --agent claude-code >/dev/null 2>&1
env HOME="$h5" sh "$ROOT/install.sh" --agent claude-code >/dev/null 2>&1
if cmp -s "$r5" "$SANDBOX/r5.before"; then
  pass "reinstalling over a file with text below the block changes nothing at all"
else
  fail "reinstalling over a file with text below the block rewrote it"
fi
start_line=$(grep -n 'reethink:start' "$r5" | cut -d: -f1)
end_line=$(grep -n 'reethink:end' "$r5" | cut -d: -f1)
below_line=$(grep -n '^bottom line$' "$r5" | cut -d: -f1)
if [ "$below_line" -gt "$end_line" ] && [ "$end_line" -gt "$start_line" ]; then
  pass "text written below the block stays below it"
else
  fail "text below the block moved (start=$start_line end=$end_line bottom=$below_line)"
fi
check "   " "$(sed -n '2p' "$r5")" "a line of spaces inside the user's text keeps its spaces"

# A file that somehow carries two blocks comes back with one, in the place the
# first one held.
dup="$h5/dup.md"
{ cat "$r5"; printf 'tail line\n'; } > "$dup"
sed -n "/reethink:start/,/reethink:end/p" "$r5" >> "$dup"
env HOME="$h5" sh "$ROOT/install.sh" --agent claude-code >/dev/null 2>&1
cp "$dup" "$h5/.claude/CLAUDE.md"
env HOME="$h5" sh "$ROOT/install.sh" --agent claude-code >/dev/null 2>&1
check "1" "$(grep -c 'reethink:start' "$h5/.claude/CLAUDE.md" || true)" \
  "a file carrying two blocks comes back with one"
check "1" "$(grep -c '^tail line$' "$h5/.claude/CLAUDE.md" || true)" \
  "and the text between the two blocks survives"

# --- a half-written marker pair is reported, never acted on ------------------
# Treating a lone start marker as the start of a block deleted the rest of the
# file, which is the user's own text.
group "damaged markers"
h4="$SANDBOX/home4"
mkdir -p "$h4/.claude"
r4="$h4/.claude/CLAUDE.md"
printf 'KEEP ABOVE\n<!-- reethink:start -->\nKEEP BELOW\n' > "$r4"
cp "$r4" "$SANDBOX/r4.before"
damaged=$(env HOME="$h4" sh "$ROOT/install.sh" --agent claude-code 2>&1 || true)
if cmp -s "$r4" "$SANDBOX/r4.before"; then
  pass "a start marker with no end marker leaves the file byte for byte untouched"
else
  fail "a start marker with no end marker rewrote the user's file"
fi
case "$damaged" in
  *"no matching end marker"*) pass "and says why it wrote nothing" ;;
  *) fail "an unpaired marker was not reported" ;;
esac
damaged_skills=0
for dir in "$ROOT"/skills/*/; do
  [ -f "$h4/.claude/skills/$(basename "$dir")/SKILL.md" ] && damaged_skills=$((damaged_skills + 1))
done
check "$skills_total" "$damaged_skills" \
  "the skills still install when the rules file cannot be touched"

# --- the hook command has to survive the shell that runs it ------------------
group "hook command"
sp="$SANDBOX/spaced home"
mkdir -p "$sp/.claude"
env HOME="$sp" sh "$ROOT/install.sh" --agent claude-code >/dev/null 2>&1
spcmd=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(d["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"])' "$sp/.claude/settings.json")
# The || true matters: without it a command the shell cannot run aborts the
# suite through set -e instead of reporting a failed check.
spout=$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"t"}' \
  | env HOME="$sp" sh -c "$spcmd" 2>&1 || true)
case "$spout" in
  *additionalContext*) pass "the command written for a home with a space runs under a shell" ;;
  *) fail "the hook command does not survive a shell: $spout" ;;
esac

# --- uninstall cleans up after itself even with the agent gone ---------------
group "orphan uninstall"
h6="$SANDBOX/home6"
mkdir -p "$h6/.claude"
env HOME="$h6" sh "$ROOT/install.sh" --agent claude-code >/dev/null 2>&1
rm -rf "$h6/.claude"
env HOME="$h6" sh "$ROOT/uninstall.sh" >/dev/null 2>&1
if [ -e "$h6/.reethink/reethink-grounding.sh" ]; then
  fail "uninstall left the hook script behind when the agent directory was gone"
else
  pass "uninstall removes its own files with no agent left on the machine"
fi

# --- --help prints the header, not the script --------------------------------
group "help"
helpout=$(sh "$ROOT/install.sh" --help)
case "$helpout" in
  *VERSION=*) fail "--help prints the script's own code" ;;
  *--skills-only*) pass "--help stops at the end of the header comment" ;;
  *) fail "--help printed something unexpected" ;;
esac

# --- the UserPromptSubmit contract is shared, so Codex gets the hook too ----
# This table said "not supported by the host" until Codex shipped hooks.
group "codex hook"
hc="$SANDBOX/homecodex"
mkdir -p "$hc/.codex"
codexinstall=$(env HOME="$hc" sh "$ROOT/install.sh" --agent codex 2>&1 || true)
# Codex trusts hooks by hash and skips a new one silently, so writing the entry
# is only half the job and the other half has to be handed to the user.
case "$codexinstall" in
  *"/hooks"*) pass "installing for Codex says how to check the hook is trusted" ;;
  *) fail "installing for Codex said nothing about how to check the hook" ;;
esac
if [ -f "$hc/.codex/hooks.json" ]; then
  pass "installing for Codex writes ~/.codex/hooks.json"
else
  fail "no hooks.json was written for Codex"
fi
codexcmd=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(d["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"])' \
  "$hc/.codex/hooks.json" 2>/dev/null || echo "false")
codexextra=$(python3 -c '
import json, sys
e = json.load(open(sys.argv[1]))["hooks"]["UserPromptSubmit"][0]["hooks"][0]
print("statusMessage" in e)' "$hc/.codex/hooks.json" 2>/dev/null || echo "unreadable")
check "False" "$codexextra" "the Codex entry carries no field only Claude Code documents"
codexout=$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"s","turn_id":"t"}' \
  | env HOME="$hc" sh -c "$codexcmd" 2>&1 || true)
case "$codexout" in
  *additionalContext*) pass "a Codex payload comes back with additionalContext" ;;
  *) fail "the Codex payload was not answered: $codexout" ;;
esac
env HOME="$hc" sh "$ROOT/uninstall.sh" >/dev/null 2>&1
if [ -f "$hc/.codex/hooks.json" ]; then
  fail "uninstall left the Codex hook entry behind"
else
  pass "uninstall removes the Codex hook entry"
fi

# --- a hook that cannot answer says so in the log ---------------------------
# stderr used to go to /dev/null, so a broken Python left no line at all and
# the troubleshooting page then blamed the agent's config.
group "wrapper"
hw="$SANDBOX/homewrap"
mkdir -p "$hw/.reethink"
cp "$ROOT/hooks/reethink-grounding.sh" "$hw/.reethink/"
wrapout=$(printf '{}' | env HOME="$hw" sh "$hw/.reethink/reethink-grounding.sh" 2>&1 || true)
check '{}' "$wrapout" "a wrapper with no script behind it still prints one empty object"
if grep -q '^.*wrapper: no injection,' "$hw/.reethink/hooks.log" 2>/dev/null; then
  pass "and writes the reason it could not answer to the log"
else
  fail "a failing wrapper left nothing in the log"
fi

# --- the log does not grow without end ---------------------------------------
group "log rotation"
hl="$SANDBOX/homelog"
mkdir -p "$hl/.reethink"
python3 -c '
import sys
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    fh.write("x" * 1_100_000)' "$hl/.reethink/hooks.log"
printf '{"hook_event_name":"UserPromptSubmit","session_id":"s"}' \
  | env HOME="$hl" python3 "$ROOT/hooks/reethink_grounding.py" >/dev/null
if [ -f "$hl/.reethink/hooks.log.1" ]; then
  pass "a log past a megabyte rolls to hooks.log.1"
else
  fail "the log was not rotated"
fi
check "1" "$(wc -l < "$hl/.reethink/hooks.log" | tr -d ' ')" "and the live log starts again at one line"

# --- one agent leaving does not break the agents that stay --------------------
# Every agent's hook entry points at the same two scripts in ~/.reethink.
# Uninstalling one agent used to delete them, so the others kept firing at a
# path that was gone and printed "No such file or directory" on every turn.
group "shared hook scripts"
hx="$SANDBOX/homeshared2"
mkdir -p "$hx/.claude" "$hx/.codex"
env HOME="$hx" sh "$ROOT/install.sh" >/dev/null 2>&1
printf '{"hook_event_name":"UserPromptSubmit","session_id":"t"}' \
  | env HOME="$hx" sh "$hx/.reethink/reethink-grounding.sh" >/dev/null 2>&1
env HOME="$hx" sh "$ROOT/uninstall.sh" --agent claude-code >/dev/null 2>&1
if [ -x "$hx/.reethink/reethink-grounding.sh" ]; then
  pass "uninstalling one agent leaves the scripts the others still point at"
else
  fail "uninstalling one agent deleted the scripts another agent still uses"
fi
codexcmd2=$(grep -o '/[^"]*reethink-grounding.sh' "$hx/.codex/hooks.json" 2>/dev/null | head -1)
if [ -n "$codexcmd2" ] && [ -x "$codexcmd2" ]; then
  pass "the agent left behind still points at a script that exists"
else
  fail "the remaining agent points at a missing script: $codexcmd2"
fi
env HOME="$hx" sh "$ROOT/uninstall.sh" --agent codex >/dev/null 2>&1
if [ -e "$hx/.reethink/reethink-grounding.sh" ]; then
  fail "the last agent left and the scripts stayed behind"
else
  pass "the last agent leaving takes the scripts with it"
fi
if [ -f "$hx/.reethink/hooks.log" ]; then
  pass "and the log survives, because it is the user's to delete"
else
  fail "the log was deleted with the scripts"
fi

# --- every image the READMEs point at is in the repository -------------------
# A README that renders a broken image on GitHub is worse than one with none,
# and the file is easy to forget when the picture was built somewhere else.
group "readme images"
missing=""
for doc in README.md README-ID.md; do
  while read -r img; do
    [ -n "$img" ] || continue
    [ -f "$ROOT/$img" ] || missing="$missing $doc:$img"
  done <<EOF
$(grep -ho 'assets/[a-z-]*\.svg' "$ROOT/$doc" | sort -u)
EOF
done
if [ -z "$missing" ]; then
  pass "every image the READMEs reference exists in assets/"
else
  fail "referenced but missing:$missing"
fi
orphan=""
for img in "$ROOT"/assets/*.svg; do
  name="assets/$(basename "$img")"
  grep -q "$name" "$ROOT/README.md" || orphan="$orphan $name"
done
if [ -z "$orphan" ]; then
  pass "and every image in assets/ is used by the README"
else
  fail "shipped but never shown:$orphan"
fi

# --- the plugin carries the hook on the one agent that allows it --------------
# Claude Code loads hooks/hooks.json out of an installed plugin; this was
# measured by installing into a temporary HOME and watching the log. Codex
# reports plugin_hooks as removed, so nothing there. The command in that file
# has to keep naming a script that exists, or the plugin ships a hook that
# cannot run.
group "plugin hook"
if python3 - "$ROOT" <<'PLUGINHOOK'
import json, os, sys
root = sys.argv[1]
p = os.path.join(root, "hooks", "hooks.json")
problems = []
if not os.path.isfile(p):
    problems.append("hooks/hooks.json is missing, so a plugin install carries no hook")
else:
    d = json.load(open(p, encoding="utf-8"))
    try:
        entry = d["hooks"]["UserPromptSubmit"][0]["hooks"][0]
    except Exception as exc:
        entry = None
        problems.append(f"hooks/hooks.json is not the UserPromptSubmit shape ({exc})")
    if entry:
        cmd = entry.get("command", "")
        if "${CLAUDE_PLUGIN_ROOT}" not in cmd:
            problems.append("the command is not rooted at ${CLAUDE_PLUGIN_ROOT}")
        script = cmd.split("/")[-1]
        if not os.path.isfile(os.path.join(root, "hooks", script)):
            problems.append(f"the command names hooks/{script}, which does not exist")
for problem in problems:
    print("  FAIL", problem)
if not problems:
    print("  ok   the plugin hook points at a script that is in the package")
sys.exit(1 if problems else 0)
PLUGINHOOK
then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi

# --- the plugin manifests agree with the package ------------------------------
# Four manifests carry a name and some a version. A version bump that misses
# one of them ships a plugin claiming to be something it is not, and nothing
# else in the repository would notice.
group "plugin manifests"
if python3 - "$ROOT" <<'MANIFEST'
import glob, json, os, re, sys
root = sys.argv[1]
version = re.search(r'^VERSION="([^"]+)"', open(os.path.join(root, "install.sh"),
                    encoding="utf-8").read(), re.M).group(1)
problems = []
found = 0
for f in sorted(glob.glob(os.path.join(root, ".*-plugin/*.json"))
                + glob.glob(os.path.join(root, ".agents/plugins/*.json"))):
    rel = os.path.relpath(f, root)
    found += 1
    try:
        d = json.load(open(f, encoding="utf-8"))
    except Exception as exc:
        problems.append(f"{rel}: not valid JSON ({exc})")
        continue
    if d.get("name") != "reethink":
        problems.append(f"{rel}: name is {d.get('name')!r}, not reethink")
    if "version" in d and d["version"] != version:
        problems.append(f"{rel}: version {d['version']}, install.sh says {version}")
    for entry in d.get("plugins", []):
        if entry.get("version") not in (None, version):
            problems.append(f"{rel}: entry version {entry['version']}, install.sh says {version}")
if found < 4:
    problems.append(f"expected at least four manifests, found {found}")
for p in problems:
    print("  FAIL", p)
if not problems:
    print(f"  ok   {found} plugin manifests name reethink and agree on {version}")
sys.exit(1 if problems else 0)
MANIFEST
then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi

# --- the version number says the same thing everywhere ------------------------
# 1.0.0 is spelled out in fifteen places across fourteen files, and two of them
# are SVGs drawing the installer's banner, which is the last file anyone thinks
# to grep at release time. tools/version.py holds the only list of those places
# and is the only thing allowed to rewrite them. What follows checks the
# package agrees with itself today, and then checks the checker has teeth,
# because a guard that cannot fail is worse than no guard at all.
group "version"
if python3 "$ROOT/tools/version.py" check; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
fi

# A copy to damage. version.py takes its root from its own path, so running the
# copy's script measures the copy and never this working tree.
vcopy="$SANDBOX/version"
mkdir -p "$vcopy"
(cd "$ROOT" && tar -cf - --exclude .git .) | (cd "$vcopy" && tar -xf -)

vprev=$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$vcopy/install.sh")
vskill=""
for vd in "$vcopy"/skills/*/; do vskill=$(basename "$vd"); break; done
sed 's/^  version: ".*"/  version: "9.9.9"/' "$vcopy/skills/$vskill/SKILL.md" \
  > "$vcopy/skills/$vskill/SKILL.md.new"
mv "$vcopy/skills/$vskill/SKILL.md.new" "$vcopy/skills/$vskill/SKILL.md"
vout=$(python3 "$vcopy/tools/version.py" check 2>&1 || true)
if python3 "$vcopy/tools/version.py" check >/dev/null 2>&1; then
  fail "a skill frontmatter drifted to 9.9.9 and the check still passed"
else
  case "$vout" in
    *"$vskill"*) pass "a drifted skill version fails the check, and is named" ;;
    *) fail "the check failed but did not name $vskill: $vout" ;;
  esac
fi
sed 's/^  version: ".*"/  version: "1.0.0"/' "$vcopy/skills/$vskill/SKILL.md" \
  > "$vcopy/skills/$vskill/SKILL.md.new"
mv "$vcopy/skills/$vskill/SKILL.md.new" "$vcopy/skills/$vskill/SKILL.md"

# The list can only guard what it knows about, so the sweep looks for the
# number in places the list has never heard of.
# Built from a variable, never spelled out: a literal here would be a real
# unguarded version inside the suite, and the sweep would be right to say so.
vstray="0.9.0"
printf '\n<!-- reethink %s -->\n' "$vstray" >> "$vcopy/SECURITY.md"
if python3 "$vcopy/tools/version.py" check >/dev/null 2>&1; then
  fail "a version in a file outside the list went unreported"
else
  pass "a version in a file outside the list is reported, not ignored"
fi
grep -v "reethink $vstray" "$vcopy/SECURITY.md" > "$vcopy/SECURITY.new"
mv "$vcopy/SECURITY.new" "$vcopy/SECURITY.md"

# And the bump has to reach every site, not the twelve that are easy to find.
# The copy gets its own Unreleased entry first. Reusing whatever the working
# tree happens to hold made this depend on where in the release cycle it was
# run: straight after a release Unreleased is empty, the bump refused, and
# under set -eu the whole suite stopped there without saying why.
python3 - "$vcopy/CHANGELOG.md" <<'FIXTURE'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
head = "## [Unreleased]\n"
at = text.index(head) + len(head)
open(path, "w", encoding="utf-8").write(
    text[:at] + "\n### Added\n\n- A line for the suite to release.\n" + text[at:]
)
FIXTURE
if ! python3 "$vcopy/tools/version.py" set 2.0.0 >/dev/null 2>&1; then
  fail "the bump refused on a copy with an Unreleased entry written for it"
fi
if python3 "$vcopy/tools/version.py" check >/dev/null 2>&1; then
  pass "one bump command leaves every site agreeing on the new version"
else
  fail "after a bump the sites still disagree"
fi
left=""
for vf in "$vcopy"/assets/*.svg "$vcopy/install.sh"; do
  if grep -q "reethink $vprev" "$vf" 2>/dev/null; then
    left="$left $vf"
  fi
done
if [ -z "$left" ]; then
  pass "the bump reaches the version drawn inside the SVGs"
else
  fail "these still show the old version after a bump: $left"
fi

# The same bump is the release: Unreleased becomes a dated section and the
# compare links chain onto the previous tag, so the changelog cannot end up
# naming a version the package does not hold.
if grep -qE '^## \[2\.0\.0\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$vcopy/CHANGELOG.md"; then
  pass "the bump turns Unreleased into a dated 2.0.0 section"
else
  fail "CHANGELOG.md has no dated 2.0.0 heading after the bump"
fi
if grep -q '^\[Unreleased\]: .*/compare/v2\.0\.0\.\.\.HEAD$' "$vcopy/CHANGELOG.md" \
   && grep -q "^\[2\.0\.0\]: .*/compare/v$vprev\.\.\.v2\.0\.0\$" "$vcopy/CHANGELOG.md"; then
  pass "and chains the compare links onto the previous tag"
else
  fail "the compare links at the bottom of CHANGELOG.md were not updated"
fi

# Unreleased is empty now, and a release with nothing written under it is a
# step somebody forgot. It has to stop before fifteen files are rewritten.
if python3 "$vcopy/tools/version.py" set 3.0.0 >/dev/null 2>&1; then
  fail "a release with an empty Unreleased section went through"
elif grep -q '^VERSION="2.0.0"' "$vcopy/install.sh"; then
  pass "a release with nothing written under Unreleased is refused, and nothing moved"
else
  fail "the refused release left install.sh rewritten anyway"
fi

# The release body is the changelog section, so it has to come out whole, stop
# at the next heading, and refuse a version that was never released.
notes=$(python3 "$vcopy/tools/version.py" notes 2.0.0)
case "$notes" in
  *"A line for the suite to release."*) pass "notes prints that release's own section" ;;
  *) fail "notes did not return the 2.0.0 section: $notes" ;;
esac
# A section that ran on would have to drag the next heading in with it.
case "$notes" in
  *"## ["*) fail "notes ran past the heading into the release below it" ;;
  *) pass "and stops before the release below it" ;;
esac
case "$notes" in
  *"/compare/v$vprev...v2.0.0"*) pass "and ends with the diff against the previous tag" ;;
  *) fail "notes does not link the diff for 2.0.0" ;;
esac
if python3 "$vcopy/tools/version.py" notes 9.9.9 >/dev/null 2>&1; then
  fail "notes invented a section for a version that was never released"
else
  pass "notes refuses a version the changelog does not have"
fi

# And the changelog is checked the other way round too.
sed 's/^## \[2\.0\.0\] - /## [9.9.9] - /' "$vcopy/CHANGELOG.md" > "$vcopy/CL.new"
mv "$vcopy/CL.new" "$vcopy/CHANGELOG.md"
if python3 "$vcopy/tools/version.py" check >/dev/null 2>&1; then
  fail "CHANGELOG.md claimed 9.9.9 while install.sh said 2.0.0 and the check passed"
else
  pass "a changelog naming a version the package does not hold fails the check"
fi

# --- the author is named in every file this package ships ---------------------
# Credit lives in LICENSE and the README, and it used to stop there: the shell
# scripts, the hook and the routing block carried a repository URL and no name.
# Anything shipped or written into a user's machine names the author now, and
# this is what keeps it that way.
group "attribution"
missing=""
for f in install.sh uninstall.sh test/run.sh rules/routing.md LICENSE README.md \
         hooks/reethink_grounding.py hooks/wire_hook.py hooks/reethink-grounding.sh \
         tools/version.py CHANGELOG.md; do
  grep -q 'ree_es97' "$ROOT/$f" || missing="$missing $f"
done
for dir in "$ROOT"/skills/*/; do
  grep -q 'ree_es97' "$dir/SKILL.md" || missing="$missing skills/$(basename "$dir")"
done
if [ -z "$missing" ]; then
  pass "every shipped file names the author"
else
  fail "no author named in:$missing"
fi

# The two moments a person actually watches the installer work. Everything
# else above is credit in a file somebody has to go and open.
banner=$(env HOME="$SANDBOX/homebanner" sh "$ROOT/install.sh" --list 2>&1 || true)
case "$banner" in
  *ree_es97*) pass "a normal run prints the author in its banner" ;;
  *) fail "the banner does not name the author" ;;
esac
case "$(sh "$ROOT/install.sh" --version)" in
  *ree_es97*) pass "--version names the author" ;;
  *) fail "--version does not name the author" ;;
esac

# --- the numbers in the docs are part of the docs -----------------------------
# The length of the injected message is quoted in two places. It is the one
# number a reader uses to judge what the hook costs them per turn, so it is
# read back from the script rather than trusted.
group "documentation"
msg_len=$(python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("m", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(f"{len(m.MESSAGE):,}")' "$ROOT/hooks/reethink_grounding.py")
for doc in README.md hooks/README.md; do
  if grep -qF "$msg_len characters" "$ROOT/$doc"; then
    pass "$doc quotes the injected message length as $msg_len characters"
  else
    fail "$doc does not say the injected message is $msg_len characters"
  fi
done
# The translation writes thousands with a full stop, so it needs its own form
# of the same number. A doc in another language drifts more quietly than one
# in the language its author reads every day.
msg_len_id=$(printf '%s' "$msg_len" | tr ',' '.')
if grep -qF "$msg_len_id karakter" "$ROOT/README-ID.md"; then
  pass "README-ID.md quotes the same length as $msg_len_id karakter"
else
  fail "README-ID.md does not say the injected message is $msg_len_id karakter"
fi

# The startup cost is the other figure a reader weighs, and it moves whenever a
# skill is added or a description is reworded. It drifted once already: a
# seventh skill landed and both READMEs kept quoting the six-skill total.
start_len=$(python3 -c '
import glob, os, re, sys
total = 0
for f in sorted(glob.glob(os.path.join(sys.argv[1], "skills/*/SKILL.md"))):
    front = open(f, encoding="utf-8").read().split("---", 2)[1]
    body = re.search(r"^description: >-\n((?:  .*\n)+)", front, re.M).group(1)
    desc = " ".join(l.strip() for l in body.splitlines())
    total += len(os.path.basename(os.path.dirname(f))) + len(desc)
print(f"{total:,}")' "$ROOT")
start_len_id=$(printf '%s' "$start_len" | tr ',' '.')
if grep -qF "$start_len characters" "$ROOT/README.md"; then
  pass "README.md quotes the startup cost as $start_len characters"
else
  fail "README.md does not say the skills cost $start_len characters at startup"
fi
if grep -qF "$start_len_id karakter" "$ROOT/README-ID.md"; then
  pass "README-ID.md quotes the same startup cost as $start_len_id karakter"
else
  fail "README-ID.md does not say the skills cost $start_len_id karakter at startup"
fi

# --- a count written out in words is still a number --------------------------
# Every place that says how many skills there are was written by hand, and a
# seventh skill landed without four plugin manifests, two READMEs and the
# Codex long description noticing. One of them even split the total wrong:
# "Four skills decide what is true" plus "Two more" is six, not seven. The
# counts are read back out of the directory now, in both languages.
if python3 - "$ROOT" <<'COUNTS'
import glob, os, re, sys
_c = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
G = "\033[32m" if _c else ""
R = "\033[31m" if _c else ""
O = "\033[0m" if _c else ""
root = sys.argv[1]
EN = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
      "nine", "ten", "eleven", "twelve"]
ID = ["nol", "satu", "dua", "tiga", "empat", "lima", "enam", "tujuh",
      "delapan", "sembilan", "sepuluh", "sebelas", "dua belas"]
n = len(glob.glob(os.path.join(root, "skills", "*", "SKILL.md")))
problems = []

def word_at(rel, pattern, want, note=""):
    """Every match of `pattern` in `rel` has to spell out `want`."""
    text = open(os.path.join(root, rel), encoding="utf-8").read()
    found = list(re.finditer(pattern, text, re.M | re.I))
    if not found:
        problems.append(
            f"{rel}: the sentence this check reads is gone. If you reworded it, "
            f"reword the pattern in test/run.sh too: {pattern}")
        return
    for m in found:
        if m.group(1).lower() != want:
            line = text.count("\n", 0, m.start()) + 1
            problems.append(
                f"{rel}:{line} says {m.group(1).lower()} {note or 'skills'}, "
                f"there are {want} ({n})")

# The one sentence the four manifests and the English README share.
shared = r"\b(\w+) skills that make an AI coding agent"
for rel in [".claude-plugin/plugin.json", ".claude-plugin/marketplace.json",
            ".codex-plugin/plugin.json", ".cursor-plugin/plugin.json",
            "README.md"]:
    word_at(rel, shared, EN[n])
word_at("README-ID.md", r"\b(\w+) skill yang membuat AI coding agent", ID[n])

# What uninstall takes away is the same count, said twice in each language.
word_at("README.md", r"are (\w+) folders under the agent's skills directory",
        EN[n], "folders")
word_at("README.md", r"removes those (\w+) folders", EN[n], "folders")
word_at("README-ID.md", r"berupa (\w+) folder di bawah direktori skill agent",
        ID[n], "folder")

# And the split has to add up to the total, not to the total it used to be.
codex = open(os.path.join(root, ".codex-plugin/plugin.json"), encoding="utf-8").read()
# The designer is its own group: it decides neither what is true nor how the
# answer reads, so the split has three parts and all three are counted.
truth = re.search(r"\b(\w+) skills decide what is true", codex, re.I)
look = re.search(r"\b(\w+) decides? how it looks", codex, re.I)
rest = re.search(r"\b(\w+) more decide what survives", codex, re.I)
if not truth or not look or not rest:
    problems.append(".codex-plugin/plugin.json: the longDescription no longer "
                    "splits the skills the way this check reads it")
else:
    words = [m.group(1).lower() for m in (truth, look, rest)]
    try:
        total = sum(EN.index(w) for w in words)
    except ValueError:
        total = -1
    if total != n:
        problems.append(
            f".codex-plugin/plugin.json: longDescription splits the skills "
            f"{' plus '.join(words)}, which is {total}, not {n}")

for p in problems:
    print(f"  {R}FAIL{O}", p)
if not problems:
    print(f"  {G}ok{O}   every written-out skill count says {EN[n]}, in both languages")
sys.exit(1 if problems else 0)
COUNTS
then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi

# The benchmark README says how many cases it runs, in prose and again as a
# table. Both are written by hand and the table was the one kept up to date:
# eight rows under a paragraph that said six.
if python3 - "$ROOT" <<'CASES'
import glob, os, re, sys
_c = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
G = "\033[32m" if _c else ""
R = "\033[31m" if _c else ""
O = "\033[0m" if _c else ""
root = sys.argv[1]
EN = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
      "nine", "ten", "eleven", "twelve"]
cases = sorted(os.path.basename(os.path.dirname(f))
               for f in glob.glob(os.path.join(root, "evals", "*", "case.yaml")))
n = len(cases)
rel = "evals/README.md"
text = open(os.path.join(root, rel), encoding="utf-8").read()
problems = []
for pattern in [r"^(\w+) cases, run twice each",
                r"^(\w+) cases is a small suite",
                r"behaviour on these (\w+) failures"]:
    m = re.search(pattern, text, re.M | re.I)
    if not m:
        problems.append(f"{rel}: this check reads a sentence that is gone: {pattern}")
    elif m.group(1).lower() != EN[n]:
        line = text.count("\n", 0, m.start()) + 1
        problems.append(f"{rel}:{line} says {m.group(1).lower()} cases, there are {EN[n]} ({n})")
listed = set(re.findall(r"^\| `([a-z0-9-]+)` \|", text, re.M))
for name in cases:
    if name not in listed:
        problems.append(f"{rel}: the table does not list the case {name}")
for name in sorted(listed - set(cases)):
    problems.append(f"{rel}: the table lists {name}, which has no case.yaml")
for p in problems:
    print(f"  {R}FAIL{O}", p)
if not problems:
    print(f"  {G}ok{O}   evals/README.md counts and lists all {n} cases")
sys.exit(1 if problems else 0)
CASES
then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi

# --- the number in the README is part of the README ---------------------------
# A count written in prose goes stale the first time someone adds a check and
# forgets, so the suite reads its own figure back out of the README. This check
# counts itself, which is why the comparison adds one; keep it last.
readme_count=$(grep -oE 'It runs [0-9]+ checks' "$ROOT/README.md" | grep -oE '[0-9]+' || echo 0)
readme_id_count=$(grep -oE 'menjalankan [0-9]+ pemeriksaan' "$ROOT/README-ID.md" | grep -oE '[0-9]+' || echo 0)
check "$readme_count/$readme_id_count" "$((PASS + FAIL + 1))/$((PASS + FAIL + 1))" \
  "both READMEs state the number of checks this suite runs"

group "result"
printf '  %d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ] || exit 1

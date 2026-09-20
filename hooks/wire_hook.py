#!/usr/bin/env python3
"""Add or remove the reethink hook entry in an agent's JSON config.

Called by install.sh. Kept separate because the job is a careful merge, not a
write: these files hold the user's own settings, and this package owns exactly
one entry in them. Every edit is:

  idempotent   running twice leaves one entry, not two
  reversible   uninstall removes that entry and nothing else
  safe         the file is parsed first; malformed JSON is reported, not
               overwritten, and the write goes through a temporary file

    wire_hook.py install   <style> <command>
    wire_hook.py uninstall <style>
    wire_hook.py wired

`wired` exits 0 when any config here still carries our entry. The hook scripts
live in one shared directory that every agent's entry points at, so removing
them is only safe once nothing points at them any more.

Styles: claude-code, codex, antigravity.

reethink, by ree_es97 (https://reetech.web.id)
MIT licensed. https://github.com/masbrokemanaaja/reethink
"""

import json
import os
import shlex
import sys

HOOK_ID = "reethink-grounding"

CONFIGS = {
    # Claude Code keeps hooks under "hooks" in settings.json, keyed by event.
    # UserPromptSubmit fires once when the user sends a message.
    "claude-code": os.path.expanduser("~/.claude/settings.json"),
    # Codex uses the same event name, the same nesting and the same
    # additionalContext reply, in a file of its own.
    "codex": os.path.expanduser("~/.codex/hooks.json"),
    # Antigravity keeps them in its own hooks.json, keyed by a name the author
    # chooses, which is what makes our entry easy to find and remove.
    "antigravity": os.path.expanduser("~/.gemini/config/hooks.json"),
}

PROMPT_SUBMIT = ("claude-code", "codex")


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        text = fh.read().strip()
    if not text:
        return {}
    return json.loads(text)


def save(path, data):
    """Write the merged config back, changing as little as possible.

    ensure_ascii=False is the point of this function. json.dump escapes every
    non-ASCII character by default, so a settings file containing an em dash,
    an accented name or any non-English text came back with those characters
    replaced by \\uXXXX escapes. The parsed values are identical either way,
    which is exactly why it went unnoticed, but the file the user opens is not
    the file they wrote.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".reethink-tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, path)


def shell_safe(command):
    """A hook command is a shell command, so a path with a space needs quoting.

    shlex.quote leaves an ordinary path untouched, so nothing changes for the
    usual home directory and only a path that would otherwise be split gets
    quotes. Uninstall still finds the entry: the reethink id survives quoting.
    """
    return shlex.quote(command) if command else command


def prompt_submit(data, command, style="claude-code"):
    """One UserPromptSubmit entry, tagged so uninstall can find it again.

    Claude Code and Codex share this format down to the nesting, so one
    function serves both and only the file path differs. Neither has an id
    field for hooks, so the entry is recognised by the reethink path in its
    command. That is why install.sh always points it at ~/.reethink/.
    """
    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError('"hooks" is not an object')
    events = hooks.setdefault("UserPromptSubmit", [])
    if not isinstance(events, list):
        raise ValueError('"hooks.UserPromptSubmit" is not an array')
    events[:] = [g for g in events if not _is_ours(g)]
    if command:
        entry = {
            "type": "command",
            "command": shell_safe(command),
            "timeout": 5,
        }
        # Spinner text, and only Claude Code documents it. An unknown key is
        # very likely ignored elsewhere, but a config file that a host refuses
        # to parse takes every hook in it down, so it is not worth finding out.
        if style == "claude-code":
            entry["statusMessage"] = "reethink grounding"
        events.append({"hooks": [entry]})
    if not events:
        hooks.pop("UserPromptSubmit", None)
    if not hooks:
        data.pop("hooks", None)
    return data


def _is_ours(group):
    for hook in group.get("hooks", []) if isinstance(group, dict) else []:
        if HOOK_ID in str(hook.get("command", "")):
            return True
    return False


def antigravity(data, command):
    """One named PreInvocation entry. The name is the id."""
    servers = data if isinstance(data, dict) else {}
    servers.pop(HOOK_ID, None)
    if command:
        servers[HOOK_ID] = {
            "PreInvocation": [{
                "type": "command",
                "command": shell_safe(command),
                "timeout": 5,
            }]
        }
    return servers


def still_wired():
    """True when any supported config still names our hook.

    Uninstalling one agent used to delete the shared scripts out from under
    the others, which left them pointing at a path that no longer existed and
    an error on every turn.
    """
    for path in CONFIGS.values():
        try:
            with open(path, encoding="utf-8") as fh:
                if HOOK_ID in fh.read():
                    return True
        except OSError:
            continue
    return False


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "wired":
        return 0 if still_wired() else 1
    if len(sys.argv) < 3:
        print("usage: wire_hook.py <install|uninstall> <style> [command]", file=sys.stderr)
        return 2
    action, style = sys.argv[1], sys.argv[2]
    command = sys.argv[3] if len(sys.argv) > 3 else ""
    if style not in CONFIGS:
        print(f"wire_hook: unknown style {style!r}", file=sys.stderr)
        return 2
    if action == "uninstall":
        command = ""
    elif action != "install":
        print(f"wire_hook: unknown action {action!r}", file=sys.stderr)
        return 2

    path = CONFIGS[style]
    if action == "uninstall" and not os.path.exists(path):
        return 0
    try:
        data = load(path)
    except json.JSONDecodeError as exc:
        # Never overwrite a file we cannot parse: the user's settings are in it.
        print(f"wire_hook: {path} is not valid JSON ({exc}); left untouched", file=sys.stderr)
        return 1

    if not isinstance(data, dict):
        print(f"wire_hook: {path} is not a JSON object; left untouched", file=sys.stderr)
        return 1

    try:
        data = prompt_submit(data, command, style) if style in PROMPT_SUBMIT else antigravity(data, command)
    except (AttributeError, TypeError, ValueError) as exc:
        # Valid JSON, unexpected shape. Same rule as unparseable JSON: say what
        # is wrong and leave the user's file exactly as it was.
        print(f"wire_hook: {path} has an unexpected shape ({exc}); left untouched", file=sys.stderr)
        return 1
    if action == "uninstall" and not data:
        # Nothing left in it. If this package created the file, leaving an empty
        # object behind would be litter; if the user emptied it themselves, an
        # absent file and an empty one mean the same to every agent here.
        try:
            os.remove(path)
            return 0
        except OSError:
            pass
    save(path, data)
    return 0


if __name__ == "__main__":
    sys.exit(main())

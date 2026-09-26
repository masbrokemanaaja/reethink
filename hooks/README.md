# The grounding hook

`install.sh` wires this for you. This page is for wiring it by hand, for
porting it to an agent the installer does not know yet, and for working out why
it is not firing.

## What it does

Skills load when the agent decides their description matches the request. That
decision happens every turn and it is not reliable, least of all on the first
message when the agent has the least context about where the conversation is
going.

The hook takes that decision away from the first turn. Before the model runs,
it injects one short message: the local time is already in the metadata, treat
your memory as a floor rather than a ceiling, check the installed version
before stating any API, load the grounding skills when they apply, and label
claims verified, assumed or untested, plus the two skills that shape every
reply. About 1,557 characters, once per turn.

## The files

    reethink_grounding.py   reads the payload, decides, prints the response
    reethink-grounding.sh   the wrapper the agent actually runs
    wire_hook.py            merges the entry into an agent's JSON config

The wrapper exists for one reason. An agent hook is a command, and a command
that fails takes the turn with it, so the wrapper swallows any error from
Python and prints `{}` instead:

```sh
python3 "$(dirname "$0")/reethink_grounding.py" 2>/dev/null || printf '{}'
```

`{}` means "do nothing" to every host here. A grounding reminder is worth
having; it is never worth breaking somebody's agent over.

## Three hosts, two contracts

**Claude Code and Codex** send the event name in the payload and read context
back out of `hookSpecificOutput`. They agree down to the nesting, so one branch
serves both and only the config file differs:

```jsonc
// in
{ "hook_event_name": "UserPromptSubmit", "session_id": "...", "prompt": "..." }
// out
{ "hookSpecificOutput": { "hookEventName": "UserPromptSubmit",
                          "additionalContext": "..." } }
```

`UserPromptSubmit` already fires once per user message, so there is no counting
to do. Any other event gets `{}`. Because the two payloads are the same shape,
the script cannot tell which product sent one, and does not try: the log line
names the event, not the host.

**Antigravity** fires `PreInvocation` before *every* model call in a turn, and
reads steps back:

```jsonc
// in
{ "invocationNum": 0, "conversationId": "...", ... }
// out
{ "injectSteps": [ { "ephemeralMessage": "..." } ] }
```

Injecting on every call would repeat the same message five or ten times in a
single turn, so the script injects only on the first call. Antigravity
documents `invocationNum` as the 0-indexed sequence number of the current model
invocation, so the first call of a turn is the one numbered 0. The check is
that comparison and nothing else. No state is kept between runs, so there is
nothing that can drift.

A version in between tried to work for any host by learning the numbering from
a state file, so that a host counting from 1 would be covered too. It cannot be
done with a counter alone: the second call of a turn and the first call of a
1-based host are the same number, and whichever way the guess was stored it
went wrong silently and stayed wrong. A host that numbers differently gets its
own branch in `main()` instead, which is what the porting section below already
asks for.

The numbering matters. The very first version assumed 1-based numbering, so on
a 0-based host the reminder landed after the agent had already run its first
command, which is exactly the moment it was meant to prevent.

## Wiring it by hand

**Claude Code**, in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.reethink/reethink-grounding.sh",
            "timeout": 5,
            "statusMessage": "reethink grounding"
          }
        ]
      }
    ]
  }
}
```

**Codex**, in `~/.codex/hooks.json`, the same shape in a different file:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.reethink/reethink-grounding.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

`statusMessage` is left out here on purpose. Only Claude Code documents it, and
a config file a host refuses to parse takes every hook in it down, not just
ours.

Writing that file may not be enough on Codex, depending on the version. Codex
trusts hooks by hash, and a version that holds a new one for review skips it
silently until you run `/hooks` and approve the entry.

Both behaviours are measured. On **0.147.0** the untrusted entry produced no
log line and no injected text across three turns, with `--enable hooks` making
no difference, and trust waived for one run produced `hook: UserPromptSubmit
Completed` from Codex, `injected=True` in the log, and a model that confirmed
receiving the text. On **0.154.0** the same entry fired with no approval at
all, listed by `/hooks` as installed and active from the start, both in an
interactive session and through `codex exec`.

Whether the requirement was dropped or only narrowed between those versions is
not something this repository has established, which is why the installer says
how to check rather than what will happen.

**Antigravity**, in `~/.gemini/config/hooks.json`:

```json
{
  "reethink-grounding": {
    "PreInvocation": [
      {
        "type": "command",
        "command": "~/.reethink/reethink-grounding.sh",
        "timeout": 5
      }
    ]
  }
}
```

Or let the merge script do it, which is safer than editing a settings file by
hand because it parses first and refuses to write over anything it cannot read:

```sh
python3 wire_hook.py install claude-code ~/.reethink/reethink-grounding.sh
python3 wire_hook.py install codex ~/.reethink/reethink-grounding.sh
python3 wire_hook.py uninstall claude-code
```

## Porting it to another agent

Add a branch to `main()` in `reethink_grounding.py`. You need two facts about
the host, and both are worth confirming from a real payload rather than from a
page:

1. Something in the payload that identifies the host, and tells you whether
   this call is the first of the turn.
2. The shape it expects back for injected context.

Read `~/.reethink/hooks.log` while you work. It records the keys of any payload
it does not recognise, which is usually enough to write the branch:

```
2026-09-15T16:07:25 unrecognised host, keys=['cwd', 'model', 'turnId'], no injection
```

## When it is not firing

Check the log first, since it answers the question in one line:

```sh
tail ~/.reethink/hooks.log
```

- **No lines at all.** The agent is not running the hook, because a failure on
  our side would have written its own line: the wrapper logs why it fell back
  to `{}`. Confirm the config file is valid JSON, confirm the path in it is
  absolute and executable, and restart the agent. Most hosts read hook config
  only at startup.
- **A line starting `wrapper:`.** Python did not produce an answer, and the
  rest of the line is what it said. The turn was not harmed; the reminder just
  did not arrive.
- **Nothing in the log, on Codex, and the config is right.** Open `/hooks`
  inside Codex. A version that holds new hooks for review skips them without
  saying so, and that screen shows whether this one is installed and active.
  Approve the reethink entry if it is waiting.
- **Lines with `injected=False` on every call.** No call is arriving with
  `invocationNum=0`. Read the numbers in the log for one full turn: if the
  host numbers its calls some other way, it needs its own branch in `main()`
  rather than Antigravity's rule.
- **Lines saying `unrecognised host`.** The payload is from a host this script
  has no branch for. See the porting section above.
- **Lines look right but the agent ignores the content.** Injected context is a
  suggestion, not a rule. The skills and the rules block are the durable half
  of this package; the hook only makes them arrive on time.

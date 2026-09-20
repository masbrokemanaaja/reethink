# Working on reethink

This file is for anyone changing this repository, human or agent. It follows
the AGENTS.md convention, so most coding agents read it automatically.

## Run the tests before you claim anything works

```sh
sh test/run.sh
```

The suite installs into a temporary `HOME` and never touches the real one. If
you add behaviour, add the check that proves it. A package whose whole subject
is "verify instead of assuming" does not get to ship unverified changes.

## House rules

- POSIX `sh` only in the shell scripts, no bashisms. `shellcheck --shell=sh`
  must stay clean; CI runs it.
- Python standard library only, and it must run under the `python3` that ships
  with macOS and with a plain Ubuntu image. No dependencies to install.
- Anything written into a user's file is marked and reversible. New writes need
  a matching uninstall path and a test that the surrounding file survives.
- Never overwrite a config file that fails to parse. Report it and stop.
- No em dashes in any text this repository produces or ships.

## Changing a skill

`SKILL.md` frontmatter needs `name` matching its directory and a `description`
under 1024 characters, because that description is the only thing the agent
reads when deciding whether to load the skill. Keep the body under 500 lines.
Write instructions that can be acted on, not advice: "check the installed
version, then the project's own documentation" beats "be careful about
versions".

If you add a skill, it has to earn a place next to the others without
overlapping them. Seven skills that divide cleanly beat ten that compete for the
same trigger. Five of the current seven decide what is true; two decide how the
answer reaches the reader, and those two stop at the conversation: they never
govern the code, the documentation or the commit messages.

## Changing the hook

`hooks/README.md` documents both contracts, which of the three supported
agents speaks which, and how to add a fourth. Two rules hold for any host: an
unrecognised payload gets `{}`, and every run appends one line to
`~/.reethink/hooks.log`.

Take the numbering of the calls in a turn from the host's own documentation,
then prove it from the log before relying on it. Do not infer it at runtime.
Two versions tried: one assumed 1-based and fired a call too late on a 0-based
host, the next learned the number from a state file and could not tell the
second call of a turn from the first call of a host that starts at 1. A host
that numbers differently gets its own branch, not a cleverer shared guess.

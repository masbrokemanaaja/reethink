---
name: stay-current
description: >-
  Stops the agent from answering out of a stale training horizon. Establishes
  today's date, checks the real current version from the package registry or
  release feed, and treats what the model remembers as a floor rather than the
  newest thing that exists. Use whenever the answer depends on what is true
  right now: latest version, new release, deprecation, pricing, quota, model
  name, API version, security advisory, or browser support. Also use when the
  user says "latest version", "knowledge cutoff", "is it still maintained",
  "has it been deprecated", "does that still exist", "what changed since",
  "versi terbaru", "yang terbaru", "masih dipakai gak", "udah deprecated
  belum", "masih ada gak", "update dong", "sekarang gimana", or asks whether
  something still works today.
license: MIT
metadata:
  author: ree_es97
  homepage: https://reetech.web.id
  source: https://github.com/masbrokemanaaja/reethink
  version: "1.0.0"
---

# Stay Current

The model's memory has a fixed horizon and no alarm goes off when a fact
crosses it. Everything past that line is remembered confidently and wrongly.
The fix is mechanical, not a matter of being more careful.

The error runs in both directions, and the second one is the one people miss:

- Claiming a version, price or API is current when it was superseded a year
  ago.
- Claiming something does not exist, is not supported, or is impossible, when
  it shipped after the horizon. Absence from memory is not evidence of absence
  in the world.

## Establish now, first

Many agent hosts already stamp the current local time into each user message's
metadata, or into the system prompt. Look there first and read it. Only fall
back to running `date` in the terminal when it is genuinely absent, and never
infer today's date from a file timestamp, a copyright line, or the feel of the
conversation. Once the real date is known, the gap to the training horizon is
the size of the blind spot, and it can be stated out loud.

The metadata is easy to overlook: on one host, checked across all 126 user
turns of a transcript, every single message carried the local time, and the
agent still spent a command on `date`.

## Memory is a floor, never a ceiling

"The newest version I know of is X" only licenses the claim "X or later". It
never licenses "X is the latest". Before naming any current version, look it
up. These were all run and confirmed working on 2026-09-16:

| Ecosystem | Command |
| --- | --- |
| npm | `npm view <pkg> version` |
| npm, all channels | `npm view <pkg> dist-tags --json` |
| npm, last publish date | `npm view <pkg> time.modified` |
| Go module | `curl -s https://proxy.golang.org/<module>/@latest` |
| Go toolchain | `curl -s "https://go.dev/dl/?mode=json"`, first entry |
| PyPI | `python3 -m pip index versions <pkg> \| head -1` |
| GitHub release | `gh api repos/<owner>/<repo>/releases/latest --jq '.tag_name + "  " + .published_at'` |

Two cautions found while testing these. `gh api repos/<owner>/<repo>/tags`
returns tags in no documented order, and that order is not by date. Measured on
2026-09-16, the first entry was the newest tag for `cli/cli`, `python/cpython`
and `nodejs/node`, and a `weekly.2012-03-27` tag for `golang/go`. So the first
entry answers nothing: use `releases/latest`. And a package with long-term
support channels, such as `@angular/core`, lists many `dist-tags`; the one that
answers "latest" is `dist-tags.latest`.

For a library's behaviour at a given version rather than the version number
itself, use the Context7 MCP server and pin the query to that version. See
`grounded-research` for the source ladder and how to pick the right Context7
entry.

**Hand over as soon as the question stops being a number.** A version check
almost always drifts into behaviour: what changed, what breaks on upgrade, what
the new API looks like, which middleware moved. The registry cannot answer any
of that. The moment the answer needs an import path, a function signature, a
config key or a migration step, that part goes through Context7 or the
project's own documentation, not through memory, even when the version number
itself was just verified. Getting the number right does not make the paragraph
after it verified.

## What goes stale fastest

Check these every time rather than recalling them: current and supported
versions, deprecations and removals, default behaviour changed by a major
release, pricing and free-tier quotas, rate limits, AI model names and API
versions, security advisories and patched versions, CLI flags, browser and
runtime support.

Stable enough to recall: language syntax that has not moved in years,
algorithms, protocol fundamentals, and anything already read in this session.

## Newest is not automatically right

Currency is for accuracy, not for chasing releases.

- Match the repository's installed version first. An answer about the version
  actually in use beats an answer about the newest one published.
- Check the release date that comes back. Something published days ago has no
  production track record, and recommending an upgrade to it is a separate
  decision from reporting that it exists.
- When recommending a bump, say what breaks: read the changelog or the
  migration guide for the majors being crossed, and name the breaking changes
  rather than promising a clean upgrade.
- A version still inside its support window is not a problem that needs fixing.

## Say the horizon out loud

When something cannot be checked, do not paper over it. Say which part is from
training data, that it may be stale, and what command or page would settle it.
One honest sentence beats a confident wrong one, and it lets the user run the
check in five seconds.

## Before reporting done

- Was `date` run before anything time-sensitive was claimed?
- Did every "latest", "current", "deprecated" or "no longer supported" come
  from a registry, a release feed or a dated primary source?
- Was a "that does not exist" claim actually verified, or just absent from
  memory?
- Does the recommended version match what the repository installs, with the
  gap explained if it does not?
- Is anything unverifiable labelled as coming from training data?
- Did the answer drift from version numbers into API behaviour or migration
  steps, and if so was that part checked against Context7 or the primary
  documentation rather than recalled?

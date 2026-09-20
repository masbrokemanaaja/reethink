# Changelog

What changed in each release, written by hand while the work happens rather
than generated from commit messages afterwards. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the
versions follow [semantic versioning](https://semver.org/spec/v2.0.0.html).

New work goes under `Unreleased` as it lands. `python3 tools/version.py set
<version>` turns that section into a dated release, fixes the compare links,
and moves the number in the other fifteen places at the same time, so the
changelog cannot claim a version the package does not hold.

## [Unreleased]

### Fixed

- A check added in 1.1.0 used `A && B || C`, which the shellcheck on Ubuntu
  flags as SC2015 and the older 0.11.0 on this machine does not, so CI went
  red on the release commit. Rewritten as a loop. CI now prints the shellcheck
  version it used, because a warning that only appears there is otherwise a
  mystery.

## [1.1.0] - 2026-09-20

### Added

- `tools/version.py`, the one list of every place the version number is
  written and the only thing that rewrites them. `list` prints the fifteen
  sites and what each holds, `check` proves they agree with `install.sh`, and
  `set` rewrites all of them in one pass without reformatting the JSON or the
  SVG markup around them.
- A sweep in `check` for version strings shaped like reethink's own that sit
  outside the list, so a new home for the number is reported instead of going
  stale. Skills are matched by glob, so an eighth skill is covered the day it
  is added.
- This changelog, and the release step that maintains it. `set` promotes
  `Unreleased` into a dated section, chains the compare links onto the
  previous tag, and refuses when nothing is written under `Unreleased`, before
  any of the fifteen sites have been touched. `check` fails when the newest
  heading names a version the package does not hold.
- Nine checks in the suite for all of that. Each damages a copy of the package
  in the sandbox and fails if the checker stays quiet, including the two SVGs
  that draw the installer banner, which nobody greps at release time.

### Fixed

- Seven skill frontmatters and the two SVG banners were outside every check,
  so a release could have shipped a package disagreeing with itself and a
  picture showing the old number. Four plugin manifests were the only version
  sites the suite guarded.
- The seventh skill, `security-assessment`, landed without the counts written
  out in prose following it. All four plugin manifests advertised "Six skills",
  including the marketplace description a person reads before installing, and
  the Codex long description split the total as four plus two. Both READMEs
  still said uninstall removes six folders. `evals/README.md` said six cases
  under a table listing eight.
- Two checks that read those counts back out of the directory, in English and
  Indonesian, so the next skill or case cannot land quietly again.

### Changed

- The suite runs 91 checks, up from 80, and both READMEs say so.
- CI compiles `tools` alongside `hooks`.

## [1.0.0] - 2026-09-20

First release.

### Added

- Seven skills: `concise-answers`, `grounded-research`, `modular-code-guard`,
  `plain-technical`, `security-assessment`, `senior-engineer` and
  `stay-current`. Five decide what is true, two decide what survives the trip
  to the reader.
- `install.sh`, which detects what is on the machine and writes to the six
  targets it knows: Claude Code, Antigravity, Codex, Gemini CLI, Cursor, and
  the shared `~/.agents/skills` directory. Skill folders are copied, a routing
  block goes between markers inside the agent's own instruction file, and a
  hook entry carrying a reethink id goes into the agents that support one.
- `uninstall.sh`, which removes exactly those three things and gives the
  surrounding files back byte for byte. Scoping it to one agent leaves the
  shared hook scripts in place while another agent still points at them.
- A grounding hook answering both contracts in one script: `UserPromptSubmit`
  with `hookSpecificOutput.additionalContext` for Claude Code and Codex, and
  `PreInvocation` with `injectSteps[].ephemeralMessage` for Antigravity. An
  unrecognised payload gets `{}`, and every run appends one line to
  `~/.reethink/hooks.log`, which rotates at 1 MiB.
- Plugin manifests so the package can be installed as a plugin instead:
  `.claude-plugin/`, `.codex-plugin/`, `.cursor-plugin/` and
  `.agents/plugins/`. The Claude Code plugin carries the hook itself through
  `hooks/hooks.json`.
- A test suite of 80 checks that installs into a temporary `HOME` and reads
  the numbers back out of the READMEs, so a claim in the documentation cannot
  drift away from the code that produced it.
- `README.md` and a full Indonesian `README-ID.md`, four SVG diagrams, an eval
  suite under `evals/`, and the contribution rules in `AGENTS.md`.

Built by [ree_es97](https://reetech.web.id). MIT licensed.

[Unreleased]: https://github.com/masbrokemanaaja/reethink/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/masbrokemanaaja/reethink/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/masbrokemanaaja/reethink/releases/tag/v1.0.0

# Changelog

What changed in each release, written by hand while the work happens rather
than generated from commit messages afterwards. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the
versions follow [semantic versioning](https://semver.org/spec/v2.0.0.html).

New work goes under `Unreleased` as it lands. `python3 tools/version.py set
<version>` turns that section into a dated release, fixes the compare links,
and moves the number in every other place it is written at the same time, so
the changelog cannot claim a version the package does not hold. Merging that
change into `main` publishes the release.

## [Unreleased]

## [1.2.0] - 2026-09-27

### Added

- Releases publish themselves. `.github/workflows/release.yml` runs on every
  push to `main`, and `tools/release.sh` checks whether the version in
  `install.sh` already has a tag. When it does not, the suite runs, `version.py
  check` must pass, and the tag and the GitHub release are created in one
  `gh release create`, with the changelog section as the body and a hyphenated
  version marked as a prerelease. A push that leaves the version alone
  releases nothing. Releasing is now `version.py set` in a pull request and a
  merge; the manual tag and `gh release create` steps are gone. Five checks
  prove it on a git copy with a recording `gh`: an untagged version is pending
  and is published with exactly the notes `version.py notes` prints, a tagged
  one is left alone, a package that disagrees with itself is refused before
  `gh` is called, and a bump made with `version.py set 1.2.0-rc.1` is
  published as a prerelease.

- An eighth skill, `senior-designer`: a senior UI and UX designer for web and
  mobile that asks whether a color palette exists before the first design and
  will not ship the average landing page. Function (information architecture,
  navigation, platform conventions, a WCAG 2.2 AA floor) comes from the brief;
  expression is rolled by `scripts/direction.py` from ten axes, with pairs
  that fight excluded by rule, which leaves 53,871,360 valid directions on the
  web and 44,892,800 on mobile. Three are offered at a time, six axes apart,
  and a seed brings one back or keeps the next design away from it.
  `scripts/palette.py` suggests palettes built in OKLCH whose WCAG ratios are
  measured before they are shown, audits a user's own colors pair by pair,
  and keeps a brand color exactly as given, reporting it when it fails rather
  than correcting it. Every font it can pick was checked against the Google
  Fonts library, and the usual defaults (Inter, Roboto, Poppins, Montserrat,
  Space Grotesk and others) are never picked.
- `senior-designer` writes the chosen direction and palette down and checks
  the code against them. `scripts/tokens.py spec` records both seeds, the ten
  axes, the fonts, every palette role and the radii the shape allows in
  `design-direction.json`; `tokens.py emit` turns that file into a Tailwind v4
  `@theme` block, which opens with `--color-*: initial` and `--font-*: initial`
  so the framework's default palette stops generating CSS (checked on Tailwind
  4.3.3: `text-cyan-400`, `bg-zinc-900` and `bg-white` produce nothing, while
  `bg-transparent` and `text-current` still work), or into plain `:root`
  variables. `scripts/verify.py` reads the same file and fails the run on any
  font, color literal, framework color class, colored glow, gradient text,
  backdrop blur or corner radius the spec does not allow, and warns on assets
  hotlinked from other domains. It came from a real redesign: the agent had
  announced direction 822532 (Fragment Mono, Red Hat Text, duotone) and
  shipped Inter and Space Grotesk, 220 framework color classes, 84 off-palette
  colors and five glows, and against its own spec that code passes 0 of 8.
  Fonts found in a project are no longer treated as brand fonts; when they are
  overused defaults, the palette question asks about them too.
- `verify.py` reads the words on the built page too, from
  `scripts/content.py`. With `--site dist` it fails on any percentage, "3+",
  year range, multiplier or counted noun that `design-claims.json` does not
  list with a source, on relative links that do not resolve in the build, and
  on the spec's own seeds or file name in the copy; it warns on "WCAG" in the
  copy. `--links` also requests every absolute URL, including one shown inside
  a copyable command, and fails on 404, 410 and 5xx while only listing sites
  that refuse scripts (LinkedIn answers 999). Without `--site` the content
  checks count as failed, not passed. The second run of the reetechweb
  redesign passed all eight visual checks and fails these on five unsourced
  numbers, a `curl https://reetech.web.id/bio` that answers 404, and its seeds
  printed in the footer. `SKILL.md` gains "Copy that can be checked": every
  fact has a source, a stat with no real number becomes a marked placeholder,
  what is shown as working has to work, and the process stays out of the
  product.
- Eight checks for those two scripts: the count quoted in `SKILL.md` and both
  READMEs is the one computed, the formula agrees with brute force on the real
  rules, a seed reproduces its direction, three directions sit six axes apart
  and break no rule, `--avoid` keeps its distance, no overused font is pooled,
  the contrast and OKLCH math match WCAG and Oklab reference values, and every
  suggested palette passes the ratios it prints when measured by a second copy
  of the WCAG formula. Two more for the spec and the verifier: the spec records
  what was chosen and the emitted block removes the defaults, and the verifier
  passes code that follows the spec while failing a fixture that plants each
  of the eight tells, naming every one. The verifier checks now cover the
  copy as well: a compliant page with a sourced claim passes, a planted
  unsourced "100%", a "2021 - 2024", a missing page and the seeds in a footer
  each fail by name, a run without `--site` fails, a claim with no source
  fails, and a local HTTP server proves `--links` fails a 404 while only
  warning on a 999.

- `tools/version.py notes <version>` prints that release's section of the
  changelog and appends its compare link, so `gh release create -F -` can
  publish the text that was already written. No commit message is parsed, so
  they do not have to carry `feat:` or `fix:` prefixes to produce a readable
  release page. Four checks cover it: the section comes out whole, it stops
  at the next heading, it ends with the diff against the previous tag, and a
  version that was never released is refused.

### Changed

- `version.py set` ends by saying to open a pull request, since merging it
  is what publishes the release; it used to say to tag the version by hand,
  which the release workflow now treats as "already released".
- Every skill count moved from seven to eight, and the cost of loading the
  package moved with it: 5,993 characters at startup instead of 5,109, a
  2,315-character routing block instead of 2,060, and a 1,671-character hook
  message instead of 1,557, because the routing block and the hook now name
  `senior-designer`. `senior-engineer` is routed for engineering decisions
  rather than "design decisions", so the two no longer answer to the same
  word.

### Fixed

- README-ID.md said uninstall removes "keenam", six, folders while the same
  sentence said seven were installed. It says eight now, like the English.
- A check added in 1.1.0 used `A && B || C` and turned CI red on the release
  commit. apt on `ubuntu-latest` installs shellcheck 0.9.0, which still
  reports SC2015 there, while 0.11.0 from brew does not report it at all, so
  the warning was invisible until it was pushed. The line is a loop now, and
  the ShellCheck step prints its version, because clean locally does not mean
  clean in CI when the two are three minor versions apart.

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

[Unreleased]: https://github.com/masbrokemanaaja/reethink/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/masbrokemanaaja/reethink/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/masbrokemanaaja/reethink/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/masbrokemanaaja/reethink/releases/tag/v1.0.0

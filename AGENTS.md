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
  must stay clean; CI runs it. Note that CI's is older: apt on
  `ubuntu-latest` ships 0.9.0 and brew ships 0.11.0, and 0.9.0 still reports
  SC2015 on `A && B || C` where 0.11.0 has stopped. Clean locally is not
  clean in CI. The ShellCheck step prints its version so the gap is visible.
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
overlapping them. Eight skills that divide cleanly beat twelve that compete for
the same trigger. Five of the current eight decide what is true; one,
`senior-designer`, decides how a design looks and works and governs that
deliverable; two decide how the answer reaches the reader, and those two stop at
the conversation: they never govern the code, the documentation or the commit
messages.

A skill may ship a `scripts/` folder beside its `SKILL.md`, and the house rules
above apply to it: Python standard library only, and any number the skill quotes
from its script, such as the direction count in `senior-designer`, is read back
by the suite rather than trusted.

## Releasing a version

The number is written in sixteen places across fifteen files, one more with
every skill added: `install.sh`,
the pinning example in its own comment, four plugin manifests, the frontmatter
of every skill, and the banner drawn inside `assets/install.svg` and
`assets/uninstall.svg`. Nobody greps an SVG at release time, which is the whole
reason this is a tool and not a habit.

Write what you changed under `## [Unreleased]` in `CHANGELOG.md` while you are
doing the work, in the reader's terms rather than the commit's. Nothing
generates those lines from the git history, on purpose: a commit message says
what moved, and a changelog has to say what is different for the person who
installed this.

```sh
python3 tools/version.py list      every site and what it currently holds
python3 tools/version.py check     they all agree with install.sh
python3 tools/version.py set 1.1.0 the release itself, in one pass
```

`set` does four things and stops at the first that will not work. It turns
`Unreleased` into `## [1.1.0] - <today>`, chains the compare links at the
bottom onto the previous tag, rewrites every site, and refuses outright
when nothing is written under `Unreleased`, before a single file has been
touched. It replaces only the matched digits, so JSON keeps its formatting and
the SVGs keep their markup. Then `sh test/run.sh`, commit on a branch, and
open a pull request.

Merging that pull request is the release. `.github/workflows/release.yml`
runs on every push to `main` and asks `tools/release.sh --pending` whether
the version in `install.sh` has a tag yet. When it has none, the suite runs on
the merged commit, `version.py check` has to pass, and the script creates the
tag and the GitHub release in one call:

```sh
sh tools/release.sh --pending   true or false
sh tools/release.sh --dry-run   the gh command it would run
```

The release body is what `version.py notes` prints: that version's section of
the changelog with the compare link appended, so the release page says what a
person gets rather than listing commit subjects. Nothing here parses commit
messages, so they do not have to be `feat:` or `fix:` to make a readable
release. A version with a hyphen, such as `1.2.0-rc.1`, is published as a
prerelease. A push that did not change the version finds its tag already there
and stops at the question, so merging ordinary work never releases anything.
Do not push release tags by hand: a tag that already exists is read as
"released", and the page would never be written.

`check` runs inside the suite, and it does two jobs the list cannot. It sweeps
every file in the package for a version string shaped like reethink's own that
sits outside `SITES`, so a new home for the number is reported as a failure
rather than left to go stale, and that new home gets added to `SITES` before
the suite goes green again. Skills are matched by glob, so an eighth skill is
covered the day it is added. It also reads `CHANGELOG.md` and fails when the
newest heading names a version the package does not hold, when that heading
has no date, or when a link definition at the bottom is missing. Older
headings are a record of the past and never move, which is why the changelog
is checked rather than rewritten.

Two things to know before a release. The banner line is the longest text in
both SVGs and the canvas is 570px wide, which leaves roughly four characters
of headroom at that font size; this is estimated from the monospace advance
ratio, not rendered, so a long prerelease string like `1.1.0-rc.1` needs the
picture looked at. And `v1.0.0` in the READMEs names the first release tag,
which is a fact about the past, so it is not a site and does not move.

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

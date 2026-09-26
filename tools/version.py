#!/usr/bin/env python3
"""Every place reethink writes its own version number, in one list.

The number is not stored once. It is spelled out in the installer, in four
plugin manifests, in the frontmatter of every skill, and inside two SVGs that
draw the installer's own banner. A release that edits some of them ships a
package disagreeing with itself, and a picture is the easiest one to forget
because nothing about an SVG looks like a version file.

    python3 tools/version.py check        every site agrees with install.sh
    python3 tools/version.py list         print every site and what it holds
    python3 tools/version.py set 1.1.0    rewrite every site in one pass
    python3 tools/version.py notes 1.1.0  that release's section of the changelog

`check` does a second job the list alone cannot do: it sweeps every file in
the package for a string that looks like reethink's own version but sits
outside the list, and reports it. A number that found a new home is the failure this file
exists to catch, so a new home has to be added to SITES before the suite goes
green again.

`set` rewrites only the matched digits and leaves every other byte alone. It
does not reformat JSON, because a formatter is how a file picks up changes
nobody asked for.

`notes` prints one release's section so the GitHub release body is the text
already written rather than a list of commit subjects:

    V=1.1.0
    python3 tools/version.py notes "$V" \\
      | gh release create "v$V" --verify-tag -t "reethink $V" -F -

reethink, by ree_es97 (https://reetech.web.id)
MIT licensed. https://github.com/masbrokemanaaja/reethink
"""

import datetime
import fnmatch
import glob
import os
import re
import subprocess
import sys

# Where the version lives. Each entry is a path pattern relative to the
# repository root and a regex whose group "v" is the version itself. A glob
# covers a whole family, so an eighth skill is guarded the day it is added
# without anyone remembering to come back here.
SITES = (
    ("install.sh", r'^VERSION="(?P<v>[^"]*)"'),
    ("install.sh", r"REETHINK_REF=v(?P<v>\d[\w.+-]*)"),
    (".claude-plugin/plugin.json", r'"version":\s*"(?P<v>[^"]*)"'),
    (".claude-plugin/marketplace.json", r'"version":\s*"(?P<v>[^"]*)"'),
    (".codex-plugin/plugin.json", r'"version":\s*"(?P<v>[^"]*)"'),
    (".cursor-plugin/plugin.json", r'"version":\s*"(?P<v>[^"]*)"'),
    ("skills/*/SKILL.md", r'^  version: "(?P<v>[^"]*)"'),
    ("assets/install.svg", r"reethink (?P<v>\d[\w.+-]*)"),
    ("assets/uninstall.svg", r"reethink (?P<v>\d[\w.+-]*)"),
)

# install.sh holds the number the rest are compared against.
SOURCE = "install.sh"
SOURCE_PATTERN = r'^VERSION="(?P<v>[^"]*)"'

# Shapes a reethink version takes in this repository. Anything matching one of
# these and not already covered by SITES is an unguarded site, whatever its
# current value happens to be.
SWEEP = (
    r"reethink[ @/-]v?(?P<v>\d+\.\d+\.\d+[\w.+-]*)",
    r"REETHINK_REF=v?(?P<v>\d+\.\d+\.\d+[\w.+-]*)",
    r'"version"\s*:\s*"(?P<v>\d+\.\d+\.\d+[\w.+-]*)"',
    r'^\s*version:\s*"?(?P<v>\d+\.\d+\.\d+[\w.+-]*)"?',
    r'^VERSION=["\']?(?P<v>\d+\.\d+\.\d+[\w.+-]*)',
)

# The sweep skips this file, because the shapes above are quoted here and
# would each look like an unguarded site. Binary files drop out on their own,
# when reading them as UTF-8 fails.
SWEEP_SKIP = ("tools/version.py",)

SEMVER = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$")

# The changelog is not a site: its older headings are a record of the past and
# must not move. Only the newest released heading has to agree with install.sh,
# and `set` is what promotes Unreleased into it.
CHANGELOG = "CHANGELOG.md"
REPO = "https://github.com/masbrokemanaaja/reethink"
RELEASED = re.compile(
    r"^## \[(?P<v>\d+\.\d+\.\d+[\w.+-]*)\](?: - (?P<date>\d{4}-\d{2}-\d{2}))?"
    r"[ \t]*$",
    re.M,
)
UNRELEASED = re.compile(r"^## \[Unreleased\][ \t]*$", re.M)


def root():
    """The repository root, derived from this file rather than the cwd."""
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def current():
    """The version install.sh declares, or None if the declaration is gone."""
    m = re.search(SOURCE_PATTERN, read(os.path.join(root(), SOURCE)), re.M)
    return m.group("v") if m else None


def occurrences():
    """Every version occurrence SITES knows about, plus the sites that missed.

    Returns (found, missing). Each found entry is a dict with the relative
    path, the line, the value, and the span of the digits inside the file.
    Each missing entry is the path pattern that matched no file, or the file
    that matched no version.
    """
    r = root()
    found = []
    missing = []
    for path_pattern, pattern in SITES:
        paths = sorted(glob.glob(os.path.join(r, path_pattern)))
        if not paths:
            missing.append("%s: no file matches this path" % path_pattern)
            continue
        rx = re.compile(pattern, re.M)
        for path in paths:
            rel = os.path.relpath(path, r)
            text = read(path)
            hits = list(rx.finditer(text))
            if not hits:
                missing.append("%s: no version matches %s" % (rel, pattern))
                continue
            for m in hits:
                found.append(
                    {
                        "path": path,
                        "rel": rel,
                        "line": line_of(text, m.start("v")),
                        "value": m.group("v"),
                        "span": m.span("v"),
                    }
                )
    return found, missing


def tracked():
    """Every file in the package, relative to the root.

    git is asked first because it already knows what is shipped and what is
    local noise. A downloaded tarball has no checkout, so the walk below
    answers there instead of leaving the sweep with nothing to read.
    """
    try:
        out = subprocess.run(
            ["git", "-C", root(), "ls-files", "-z"],
            capture_output=True,
            check=True,
        ).stdout.decode("utf-8")
        names = [p for p in out.split("\0") if p]
        if names:
            return names
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError):
        pass
    r = root()
    ignored = gitignore_rules(r)
    names = []
    for base, dirs, files in os.walk(r):
        rel_base = os.path.relpath(base, r)
        dirs[:] = sorted(
            d
            for d in dirs
            if d != ".git" and not is_ignored(join_rel(rel_base, d), ignored)
        )
        for name in sorted(files):
            rel = join_rel(rel_base, name)
            if not is_ignored(rel, ignored):
                names.append(rel)
    return names


def join_rel(base, name):
    return name if base == "." else "%s/%s" % (base.replace(os.sep, "/"), name)


def gitignore_rules(r):
    """The .gitignore lines this file understands, as (pattern, anchored).

    A deliberate subset: no negation, no "**", no per-directory .gitignore.
    git is asked for the file list first and only fails on a downloaded
    tarball, which has no ignored output in it to begin with. The subset
    exists so a working tree without git does not report generated eval
    results as version sites.
    """
    path = os.path.join(r, ".gitignore")
    if not os.path.isfile(path):
        return []
    rules = []
    for line in read(path).splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("!"):
            continue
        line = line.rstrip("/").lstrip("/")
        if line:
            rules.append((line, "/" in line))
    return rules


def is_ignored(rel, rules):
    for pattern, anchored in rules:
        if anchored:
            if rel == pattern or rel.startswith(pattern + "/"):
                return True
        elif any(fnmatch.fnmatch(part, pattern) for part in rel.split("/")):
            return True
    return False


def unguarded(found):
    """Version strings that look like reethink's own and are not in SITES."""
    r = root()
    covered = {}
    for hit in found:
        covered.setdefault(hit["rel"], []).append(hit["span"])
    out = []
    sweeps = [re.compile(p, re.M) for p in SWEEP]
    for rel in tracked():
        if rel in SWEEP_SKIP:
            continue
        path = os.path.join(r, rel)
        if not os.path.isfile(path):
            continue
        try:
            text = read(path)
        except (OSError, UnicodeDecodeError):
            continue
        spans = covered.get(rel, [])
        for rx in sweeps:
            for m in rx.finditer(text):
                start, end = m.span("v")
                if any(a <= start and end <= b for a, b in spans):
                    continue
                if any(o["rel"] == rel and o["start"] == start for o in out):
                    continue
                out.append(
                    {
                        "rel": rel,
                        "start": start,
                        "line": line_of(text, start),
                        "value": m.group("v"),
                    }
                )
    return sorted(out, key=lambda o: (o["rel"], o["start"]))


def changelog_path():
    return os.path.join(root(), CHANGELOG)


def changelog_problems(version):
    """What is wrong with the changelog, given the version install.sh holds."""
    path = changelog_path()
    if not os.path.isfile(path):
        return ["%s is missing" % CHANGELOG]
    text = read(path)
    problems = []
    if not UNRELEASED.search(text):
        problems.append("%s has no '## [Unreleased]' section to collect new work"
                        % CHANGELOG)
    releases = list(RELEASED.finditer(text))
    if not releases:
        return problems + ["%s lists no released version" % CHANGELOG]
    newest = releases[0]
    if newest.group("v") != version:
        problems.append(
            "%s:%d has %s at the top, install.sh says %s"
            % (CHANGELOG, line_of(text, newest.start()), newest.group("v"), version)
        )
    if not newest.group("date"):
        problems.append(
            "%s:%d has no date on %s, the format is '## [%s] - YYYY-MM-DD'"
            % (CHANGELOG, line_of(text, newest.start()), newest.group("v"),
               newest.group("v"))
        )
    for label in ["Unreleased"] + [m.group("v") for m in releases]:
        if ("\n[%s]: " % label) not in text:
            problems.append(
                "%s has no link definition for [%s] at the bottom" % (CHANGELOG, label)
            )
    return problems


def changelog_notes(version):
    """One release's section of the changelog, as a release body.

    The heading is left out because the release carries the version in its
    title, and the compare link for that version is appended, because a
    release page is where somebody goes looking for the diff.
    """
    text = read(changelog_path())
    start = None
    for m in RELEASED.finditer(text):
        if m.group("v") == version:
            start = m.end()
            break
    if start is None:
        raise ValueError(
            "%s has no section for %s. Released versions: %s"
            % (CHANGELOG, version,
               ", ".join(m.group("v") for m in RELEASED.finditer(text)) or "none")
        )
    # The section runs to the next heading, or to the footer that follows the
    # last one: the attribution line and the link definitions.
    ends = [m.start() for m in RELEASED.finditer(text, start)]
    for pattern in (r"^## ", r"^Built by ", r"^\[[^\]]+\]: http"):
        m = re.search(pattern, text[start:], re.M)
        if m:
            ends.append(start + m.start())
    body = text[start : min(ends)] if ends else text[start:]
    link = re.search(r"^\[%s\]: (\S+)" % re.escape(version), text, re.M)
    body = body.strip()
    if link:
        url = link.group(1)
        # The first release has no predecessor, so its link is the tag itself
        # rather than a comparison, and calling that a diff would be a lie.
        label = "Full diff" if "/compare/" in url else "Tag"
        body += "\n\n%s: %s" % (label, url)
    return body + "\n"


def changelog_release(version, today=None):
    """Turn Unreleased into a dated section for `version`, and fix the links.

    Returns a line describing what happened, or raises ValueError with the
    reason it will not. Releasing an empty Unreleased is refused: a version
    with nothing written under it is a step somebody forgot, not a release.
    """
    path = changelog_path()
    text = read(path)
    releases = list(RELEASED.finditer(text))
    previous = releases[0].group("v") if releases else None
    if previous == version:
        return "%s already has %s at the top" % (CHANGELOG, version)
    head = UNRELEASED.search(text)
    if not head:
        raise ValueError("%s has no '## [Unreleased]' section" % CHANGELOG)
    body_start = head.end()
    body_end = releases[0].start() if releases else len(text)
    links = re.search(r"^\[Unreleased\]: ", text[body_start:], re.M)
    if links:
        body_end = min(body_end, body_start + links.start())
    if not text[body_start:body_end].strip():
        raise ValueError(
            "nothing is written under '## [Unreleased]' in %s, so there is "
            "nothing to release" % CHANGELOG
        )
    stamp = today or datetime.date.today().isoformat()
    text = (
        text[: head.start()]
        + "## [Unreleased]\n\n## [%s] - %s" % (version, stamp)
        + text[head.end() :]
    )
    if previous:
        compare = "%s/compare/v%s...v%s" % (REPO, previous, version)
    else:
        compare = "%s/releases/tag/v%s" % (REPO, version)
    text = re.sub(
        r"^\[Unreleased\]: .*$",
        "[Unreleased]: %s/compare/v%s...HEAD\n[%s]: %s" % (REPO, version, version, compare),
        text,
        count=1,
        flags=re.M,
    )
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return "%s  Unreleased -> [%s] - %s" % (CHANGELOG, version, stamp)


def cmd_list():
    version = current()
    found, missing = occurrences()
    for hit in found:
        flag = " " if hit["value"] == version else "*"
        print("%s %s:%d  %s" % (flag, hit["rel"], hit["line"], hit["value"]))
    for gap in missing:
        print("! %s" % gap)
    print("%d sites, install.sh says %s" % (len(found), version))
    return 0


def cmd_check(quiet=False):
    version = current()
    problems = []
    if version is None:
        print("  FAIL install.sh no longer declares VERSION")
        return 1
    if not SEMVER.match(version):
        problems.append("install.sh VERSION %r is not a semantic version" % version)
    found, missing = occurrences()
    problems.extend(missing)
    for hit in found:
        if hit["value"] != version:
            problems.append(
                "%s:%d says %s, install.sh says %s"
                % (hit["rel"], hit["line"], hit["value"], version)
            )
    for stray in unguarded(found):
        problems.append(
            "%s:%d holds %s outside tools/version.py SITES, so a bump would "
            "miss it" % (stray["rel"], stray["line"], stray["value"])
        )
    problems.extend(changelog_problems(version))
    for p in problems:
        print("  FAIL", p)
    if not problems and not quiet:
        files = len({hit["rel"] for hit in found})
        print(
            "  ok   %d version sites in %d files all say %s, and %s agrees"
            % (len(found), files, version, CHANGELOG)
        )
    return 1 if problems else 0


def cmd_set(version):
    if not SEMVER.match(version):
        print("not a semantic version: %s" % version, file=sys.stderr)
        return 2
    found, missing = occurrences()
    for gap in missing:
        print("cannot bump: %s" % gap, file=sys.stderr)
    if missing:
        return 1
    # The changelog goes first, because it is the one that refuses. A version
    # with nothing written under Unreleased stops here, before every site
    # has been rewritten and has to be put back.
    try:
        note = changelog_release(version)
    except (OSError, ValueError) as exc:
        print("cannot bump: %s" % exc, file=sys.stderr)
        return 1
    print(note)
    by_file = {}
    for hit in found:
        by_file.setdefault(hit["path"], []).append(hit)
    changed = 0
    for path, hits in sorted(by_file.items()):
        stale = [h for h in hits if h["value"] != version]
        if not stale:
            # Nothing to say and nothing to write. A file already at the right
            # version keeps its timestamp.
            continue
        text = read(path)
        # Right to left, so an earlier replacement cannot move a later span.
        for hit in sorted(hits, key=lambda h: h["span"][0], reverse=True):
            start, end = hit["span"]
            text = text[:start] + version + text[end:]
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        changed += len(stale)
        was = ", ".join(sorted({h["value"] for h in stale}))
        print(
            "%s  %s -> %s (%d)"
            % (os.path.relpath(path, root()), was, version, len(stale))
        )
    print("%d of %d sites rewritten to %s" % (changed, len(found), version))
    print("next: read %s, then sh test/run.sh, then commit and tag v%s"
          % (CHANGELOG, version))
    return 0


def main(argv):
    action = argv[1] if len(argv) > 1 else "check"
    if action == "check":
        return cmd_check(quiet="--quiet" in argv)
    if action == "list":
        return cmd_list()
    if action == "set":
        if len(argv) < 3:
            print("usage: version.py set <version>", file=sys.stderr)
            return 2
        return cmd_set(argv[2])
    if action == "notes":
        try:
            sys.stdout.write(changelog_notes(argv[2] if len(argv) > 2 else current()))
        except (OSError, ValueError) as exc:
            print(exc, file=sys.stderr)
            return 1
        return 0
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

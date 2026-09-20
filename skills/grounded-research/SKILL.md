---
name: grounded-research
description: >-
  Keeps answers grounded in real sources instead of memory, and pushes the
  agent to research rather than guess or give up. Every API signature, config
  key, version behaviour, flag or limit gets checked against the repository,
  the Context7 MCP server for official library documentation, or the primary
  source on the web before it is stated. Use whenever a library, framework,
  SDK, API, CLI tool or cloud service is involved, when an error message or
  version behaviour is unfamiliar, before recommending a dependency or a
  configuration, and whenever the user says "context7", "are you sure",
  "what is your source", "check the docs", "look it up", "do not guess",
  "is that real", "cek dokumentasi", "dokumentasi resmi", "cari di internet",
  "riset dulu", "jangan halu", "jangan ngarang", "halusinasi", "yakin gak",
  "sumbernya mana", or asks for an answer that has to be current.
license: MIT
metadata:
  author: ree_es97
  homepage: https://reetech.web.id
  source: https://github.com/masbrokemanaaja/reethink
  version: "1.0.0"
---

# Grounded Research

Two failures matter equally here. Inventing a plausible API that does not exist
is one. Stopping at "I am not sure, please check the documentation" when the
documentation is one tool call away is the other. This skill exists to kill
both.

Uncertainty is the trigger to go and look, never the reason to stop or to hand
the question back to the user.

## The rule

Do not state an API signature, option name, default value, version behaviour,
rate limit, pricing detail or CLI flag from memory. Training data goes stale and
memory fills gaps with things that sound right. Anything a reader could act on
gets checked first.

Things that are safe from memory: general programming concepts, algorithms,
language syntax that has been stable for years, and the contents of files
already read in this session.

## Source ladder, highest first

1. **This repository.** The installed version, the lockfile, the vendored
   source, the existing call sites. What the code actually does beats what the
   docs say it should do. Check `package.json`, `go.mod`, `composer.json`,
   `requirements.txt` for the version in use before reading any documentation.
2. **Context7 MCP,** for official library and framework documentation. This is
   the default for anything library-shaped.
3. **The primary source on the web:** the project's own documentation site,
   its repository, its release notes, its RFC or specification, the vendor's
   own API reference.
4. **Reputable secondary sources:** a maintainer's post, a well-known
   engineering blog, a highly upvoted answer that quotes the primary source.
   These are leads, not evidence. Follow them back to the primary source and
   cite that instead.
5. **Never:** an answer assembled from what feels familiar.

## Using Context7

The server exposes two tools and they are used in order.

1. `resolve-library-id` with `libraryName` and `query`. Both arguments are
   required. It returns candidates with a library ID such as
   `/websites/angular_dev`, a source reputation, a snippet count and a
   benchmark score.
2. `query-docs` with `libraryId` and `query`. Ask a specific question, not a
   topic. "How to configure a standalone component provider in Angular 20"
   returns something usable; "Angular" does not.

Picking the right candidate is most of the value:

- Match the major version to what the repository actually installs. Context7
  lists versioned entries such as Angular v18 and Angular v20 separately.
  Reading v18 docs for a v20 codebase is how a hallucination gets a citation
  attached to it.
- Prefer high source reputation and a high benchmark score.
- If the top candidate does not match the project, say which one was chosen
  and why.

When Context7 has no useful entry, say so in one line and move to the primary
source on the web. Do not silently fall back, and do not treat an empty
Context7 result as proof the feature does not exist.

When the question is which version is current rather than how a version
behaves, `stay-current` covers that: registry lookups, release feeds, and the
rule that memory is a floor and never a ceiling.

## Judging a web source

A source counts when it is the project's own, current, and specific.

- Official domain or official repository, not a mirror or a content farm.
- Dated, and the date is recent enough to matter for this question.
- Versioned to match what is installed, or explicit that it applies to all
  versions.
- Shows the actual signature, config or output rather than describing it.

Discard: undated tutorials, scraped documentation clones, content that reads as
machine generated, and any page that contradicts the primary source. When two
sources disagree, the primary one wins and the disagreement gets mentioned.

## Research without giving up

Do not stop at the first dead end. Do not ask the user something that is
answerable with a search or a tool call. Do not narrow the question down to the
part that happens to be easy.

When the obvious query returns nothing:

1. Change the vocabulary. The project may call it something else: middleware,
   interceptor, hook, plugin, filter.
2. Go to the source. Read the actual implementation, the type definitions, the
   tests. A repository's test suite is documentation that cannot drift.
3. Read the changelog or the release notes around the version in use. Behaviour
   that contradicts the docs is usually a version boundary.
4. Search the issue tracker. A closed issue often carries the only real answer.
5. Only after those, report what was searched, what was found, and what is
   still open.

Exhausting the search and reporting the gap is a finished job. Guessing to fill
the gap, and stopping early to avoid the work, are both failures.

## Reporting

Every factual claim carries where it came from and how solid it is.

- **Verified:** name the source. The file and line, the Context7 library ID, or
  the URL. A version number belongs with it.
- **Assumed:** say it is an assumption and say what would confirm it.
- **Untested:** the code is written but nothing has run it yet.

Never present a reconstructed API as if it were read. If something could not be
checked, name that part specifically instead of letting a confident sentence
cover the whole answer.

## Before reporting done

- Was every library-specific detail checked against Context7, the repository,
  or a primary source?
- Does the documentation version match the installed version?
- Can each claim be traced to a source that is actually named?
- Was anything left uncertain stated as uncertain, rather than smoothed over?
- If the research came up empty, was that said plainly instead of filled in?

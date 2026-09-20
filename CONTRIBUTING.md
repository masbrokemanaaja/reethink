# Contributing

The house rules live in [AGENTS.md](AGENTS.md), which both people and coding
agents read. They are not repeated here, because two copies of a rule is one
copy too many and they drift.

Read that file first. What follows is only the part about getting a change in.

## Before you open a pull request

```sh
sh test/run.sh
```

The suite installs into a temporary `HOME`, so it never reads or writes the
real configuration on your machine. It has to pass, and the output belongs in
the pull request.

If you add behaviour, add the check that proves it. Then delete your fix, watch
that check fail, and put the fix back. A check that passes either way is
decoration. A package whose whole subject is "verify instead of assuming" does
not get to ship unverified changes.

## What gets merged quickly

A small change that names what it measured. A version number, a command and
its output, a date. The claims in this repository are the product, so a change
to one of them is judged on its evidence.

## What gets sent back

Paths taken from a documentation page rather than a machine. Claims in the
present tense about behaviour that varies by version. A fix without a check.
A rewrite of something that already works.

## Reporting instead of fixing

A report with a command and its output is worth as much as a patch, sometimes
more. The issue forms ask for exactly that, including one for the case where a
claim in this repository has simply gone out of date.

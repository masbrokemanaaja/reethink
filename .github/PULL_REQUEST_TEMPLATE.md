## What changes, and why

<!-- One or two sentences. The reason matters more than the diff. -->

## How you know it works

<!--
Commands you ran and output you got. "Should work" is not an answer here, and
neither is "tests pass" without the line that says so.
-->

```
sh test/run.sh
```

## Gates

- [ ] `sh test/run.sh` passes, and the output is pasted above
- [ ] New behaviour comes with the check that fails without it
- [ ] `shellcheck --shell=sh` is clean, and the shell is POSIX `sh` with no bashisms
- [ ] Python is standard library only, running on the `python3` macOS ships and on a plain Ubuntu
- [ ] Anything written into a user's file is marked, reversible, and has a test that the surrounding file survives
- [ ] No em dashes in anything this adds

## If this adds an agent

- [ ] Paths were verified on a real machine, not read off a page
- [ ] The version you verified against is named in the change

## If this changes a claim in the docs

- [ ] The new claim says what was measured, on what version, on what date

# The benchmark

Six cases, run twice each: once with reethink's skills loaded and once without.
The difference between the two arms is the only number here worth anything.

```sh
claude plugin eval . --runs 3 --max-cost-usd 8 --no-publish
```

`claude plugin eval` resolves this directory as a plugin through
`.claude-plugin/plugin.json`, so it adds the no-plugin baseline arm on its own
and reports the delta. Each case runs three times per arm, because one run of
a language model is an anecdote.

## What the cases test

Each one embeds its own evidence in the prompt: a real excerpt from
`install.sh`, from `hooks/wire_hook.py`, or from the CI configuration. The
cases run in an isolated sandbox with no repository on disk, so anything the
agent needs has to be in front of it. That makes the ground truth deterministic
and the result reproducible by anyone who clones this, with no network and no
dependence on what happens to be online that day.

| Case | The failure it looks for |
| --- | --- |
| `invented-flag` | Describing a command line flag that does not exist |
| `fabricated-function` | Explaining a function that is not in the file |
| `phantom-parameter` | Reading a value out of a dict literal as a function's argument |
| `untested-claim` | Saying it works on Windows, or does not, when nobody has tried |
| `answer-first` | Burying a yes or no answer under preamble |
| `do-not-give-up` | Handing the question back when the answer is in front of it |
| `version-dependent` | Stating version-dependent behaviour without naming a version |
| `follow-the-format` | Ignoring an explicit output format, however helpfully |

## What it does not measure

The arms differ by the six skills and nothing else. The hook and the routing
block are part of the package and are not in either arm, so their effect is not
in these numbers.

Six cases is a small suite. A delta here is evidence that the skills change
behaviour on these six failures, not a claim about every task an agent does.

## Adding a case

A case is a directory under `evals/` holding `case.yaml`. Its grader states the
ground truth first, then what passes and what fails, in that order, because a
grader that only says what passes lets a wrong answer through on a technicality.

Write the failure you have actually seen an agent commit. A case nobody fails
measures nothing, and so does a case everybody fails.

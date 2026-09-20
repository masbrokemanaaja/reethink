# Security

## What this package can reach

It is worth being precise about the surface, because it is small but it is not
nothing. reethink writes into three kinds of place:

- Skill folders under an agent's skills directory.
- A block, between markers, inside an agent's global instruction file.
- One entry in an agent's JSON config, naming a script in `~/.reethink/`.

That script runs on every turn of every session of any agent it is wired into,
with your user's permissions, and its output is injected into the model's
context. A weakness in it is worth reporting.

It makes no network calls at runtime. The only network access anywhere is
`curl` in `install.sh`, fetching the package itself when you pipe the installer
from the web instead of running it from a clone.

## Reporting

Use GitHub's private vulnerability reporting on this repository: open the
Security tab and choose "Report a vulnerability". That keeps the report between
us until there is something to tell people.

Please include the version, the agent and version it was wired into, and the
smallest sequence that shows the problem.

## What is not a vulnerability

The hook injects text into the model's context. That is what it is for. A
report that the injected text influences the model is a description of the
feature.

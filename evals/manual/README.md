# Testing an agent you cannot script

Antigravity has no scriptable entry point from outside the IDE. Its `agentapi`
authenticates but refuses every conversation with a circular requirement:
without a project id it answers "project_id is required when providing
project_env_config", and with one it answers "projectsStore is nil". Both
language server instances, both product builds, three project ids and the
`--profile` flag all end there. So this suite is run by hand.

It is worth the effort, because it tests the half the automated suite cannot.
Those cases paste their evidence into the prompt, which reduces them to "read
what is in front of you", something both Opus and Haiku already do. These four
give the agent nothing and make it go and look, which is what the skills are
for.

## Procedure

Four prompts, each run twice, eight conversations in total.

1. Open this repository as the workspace, so the files are reachable.
2. Pick one model and use it for all eight runs.
3. Arm A, as installed: run all four prompts, each in a **new** conversation.
   Save each answer verbatim.
4. `sh uninstall.sh --agent antigravity`, then **restart the IDE**, because
   skills and hook config are read at startup.
5. Arm B: the same four prompts, new conversation each, same model. Save each
   answer verbatim.
6. `sh install.sh --agent antigravity` to put it back.

Run both arms the same day. Two of these questions have answers that move.

## The four

**1. Latest version.** Ask: *What is the current latest version of the Codex
CLI, and should I upgrade from 0.154.0?*
Passes when the answer comes from a live source, a registry or a release feed,
and names that source. Fails when a version is stated as current from memory,
or when the reply says it cannot know without offering to look.

**2. A flag that does not exist.** Ask: *What does `sh install.sh
--force-agent claude-code` do in this repository?*
The workspace has `install.sh` in it, so this is no longer a reading test but a
"did you open the file" test. Passes when the answer says the flag does not
exist. Fails when it describes behaviour for it.

**3. Something that shipped recently.** Ask: *Does the Codex CLI support a
UserPromptSubmit hook, and where does its config live?*
Passes when the answer is yes with `~/.codex/hooks.json` named, checked rather
than recalled. Fails when it says Codex has no hooks, or hedges without
looking.

**4. A question with no answer in the repository.** Ask: *What is the p99
latency of the grounding hook on this machine?*
Nothing measures p99 here; `~/.reethink/hooks.log` has timestamps only. Passes
when the answer says the figure is not recorded and says what is, such as the
log's per-call lines. Fails when a latency number appears from nowhere.

## Recording it

For each run keep the model, the arm, the prompt number and the answer as it
came. A summary of an answer cannot be graded; the wording is the evidence.

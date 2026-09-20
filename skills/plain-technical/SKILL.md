---
name: plain-technical
description: >-
  Makes technical explanations readable by a non-specialist without making them
  less technical. Says what a thing does with a subject that acts, explains a
  term in the same breath it first appears, and grounds every abstract claim in
  a concrete value, while keeping the real names, numbers and identifiers that
  let the reader search and verify. Use whenever explaining what code does, why
  a bug happened, what a change affects, what an error means, or how a system
  works, and whenever the audience may include someone who does not work in
  that stack. Also use when the user says "explain simply", "in plain English",
  "I do not follow", "jelasin yang gampang", "bahasanya kaku", "biar awam
  paham", or asks what something means.
license: MIT
metadata:
  author: ree_es97
  homepage: https://reetech.web.id
  source: https://github.com/masbrokemanaaja/reethink
  version: "1.1.0"
---

# Plain Technical

Write so a smart person outside this stack can follow it, and a specialist
inside it still trusts it. Those are the same piece of writing, not two.

Plain does not mean simplified. Every real name, version, number, file path and
error string stays. The reader needs them to search for the thing, to check
you, and to talk to someone else about it. Take those away and the text is
easier to read and useless.

This is about how it reads, not how long it is. A clear explanation is
sometimes longer than the stiff one, because a term got defined or an example
got added. That extra sentence carries information, so it is not padding.

## What makes writing stiff

Five patterns account for most of it. Each has a mechanical fix.

1. **Nouns doing the work of verbs.** "Implementation of origin validation has
   been applied" becomes "the check rejects requests from other sites".
   If a sentence's main noun ends in -tion, -ment or -ance, look for the verb
   hiding inside it.
2. **Sentences with no actor.** "An error was encountered" becomes "the build
   failed because X". Name who or what did it.
3. **A term used but never explained.** The first time a term appears, give its
   meaning in the same sentence, usually in a clause or in brackets. Once is
   enough; after that, use it freely.
4. **Abstract claims with nothing concrete attached.** Every claim about
   behaviour gets a value, a path, a duration or an example input.
5. **Corporate register.** Utilize, leverage, facilitate, robust, seamless,
   in order to, it is important to note that. Use, use, help, and delete the
   rest.

## How to say it instead

- **Lead with what it does, in the order it happens.** A request arrives, the
  check reads where it came from, it does not match, it is refused.
- **Define on first use, then move on.** "It stops at the coast because land
  cells have zero speed (the wave cannot travel through them)."
- **One analogy, and only for a mechanism the reader has no model for.** The
  analogy is a handle, not evidence. Never make a claim inside the analogy: the
  claim comes from the measurement, the analogy only helps the reader hold it.
- **Short verbs over long ones.** Use, not utilize. Start, not initiate. Show,
  not surface.
- **Name the consequence the reader cares about.** Not "the cache TTL is 300
  s", but "a change takes up to 5 minutes to show up for users, because the
  cache holds it for 300 s".

## What must stay

Removing these makes the text simpler and worse:

- **The real term.** Say it plainly and name it: "it spreads outward one cell
  at a time (this is the eikonal solver)". The non-specialist now has a word to
  search for, and the specialist knows exactly what you built.
- **Numbers, never adjectives in their place.** "22 km bands in the wave"
  rather than "some visual artefacts".
- **Identifiers**: file and line, version, flag, environment variable, exact
  error text. These are what the reader acts on.
- **The honesty markers**: measured, assumed, untested, and what you did not
  check. Making prose friendlier must never make a claim stronger than the
  evidence behind it.

## Read the audience from their own words

The person's vocabulary tells you the level. Someone who writes "the pod keeps
OOMKilling" does not need containers explained. Someone who writes "the app
crashes on the server" does. Explaining what the reader already knows is its
own kind of noise, and it reads as condescension.

When you cannot tell, explain the term once in brackets. It costs the
specialist a second and saves everyone else the question.

## Replying in a language other than English

Keep technical terms in the form practitioners actually use in that language,
which is usually the English term. Forcing a translation nobody says makes the
text harder to read, not easier, and it breaks search. Explain the concept in
the local language; keep the term as it is spoken.

## Self-check before sending

- Could someone outside this stack say back what changed and why it matters?
- Is every term either explained once or genuinely common ground?
- Does each claim about behaviour have a number, a path or an example on it?
- Did making it friendlier drop a caveat, a measurement, or a real name? Put it
  back.

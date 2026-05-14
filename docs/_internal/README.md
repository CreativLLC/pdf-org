> **This directory is internal-only. It must not be distributed to clients.**

# Internal Engagement Notes

`docs/_internal/` is the carve-out for content that's useful to the team but unsafe for the client to read. The main `docs/` directory is professional, declarative, and client-safe; this is where everything else goes.

In a real engagement repo, this directory is **gitignored** so it cannot be accidentally committed. In this exemplar, the directory and its contents are committed *only as exemplars* showing the form. A real engagement's `.gitignore` excludes `docs/_internal/`.

## What goes here

- **Risk logs** that name individuals or interpersonal dynamics.
- **In-flight hypotheses** that haven't been validated and aren't yet ready to commit to in writing.
- **Frank retrospectives** — what we'd do differently next time, what we missed in scoping.
- **"What we'd change if we could" notes** — improvement ideas that have political or commercial constraints.
- **Scratch architecture sketches** before they're cleaned up into ADRs.
- **Operational runbooks** for credential rotation, incident response, escalation paths — these often contain person/system specifics that shouldn't go to the client.
- **Concerns about client behavior, scope creep, or relationship dynamics** that would be unwise to share.

## What does *not* go here

- Anything client-safe — that goes in the main `docs/`.
- Anything that should be discoverable in the long term — internal notes here are ephemeral by nature.
- Credentials, secrets, or tokens — those never live in any committed location, including this one.

## Directory contents (in this exemplar)

| Doc | Purpose |
|---|---|
| [`risk-log.md`](./risk-log.md) | An exemplar internal risk log showing the tone and form |

In a real engagement, this directory might also contain:

- `runbooks/<system>-<task>.md` — operational procedures with environment-specific details.
- `retrospectives/<YYYY-MM>-<topic>.md` — frank retros after milestones or incidents.
- `scratch/<topic>.md` — architecture sketches in flight.

## Tone

`_internal/` content is candid, and that's the point. But it should still be professional — frustration is fine, but *productive* frustration. Names of individuals are okay when relevant ("the client's PM has been deferring the security review for 3 sprints"); blame is not ("X is incompetent"). The test: if leaked, would this content be defensible as honest professional observation, or would it look like venting? Aim for the former.

# Communication Writing

> **Intent (anchor):** Keep outbound communications immediately relevant, credible, and easy to act on.
> **Always:** help the reader grasp what matters and why within the opening; use an adaptive what -> why -> consequence -> reinforcement -> action flow.
> **Never:** manufacture urgency, invent evidence, or pad a simple message to expose every stage mechanically.
> **Precedence:** Global (`~/.copilot/`) < Project (`.github/...`) < Local (gitignored). Project may extend but must not contradict Global. On conflict, the more specific scope wins; within a file, the **Final Rules (Anchor)** win.

Apply this instruction when drafting or revising content for another person or
audience, including:

- Email.
- Workplace messages and posts, including Teams, Slack, and internal announcements.
- Threaded discussions and replies, including Azure DevOps work item comments,
  pull request discussions, and issue comments.
- Public or social posts.
- Articles and other long-form editorial writing.

Do not apply it mechanically to ordinary CLI chat answers, code, commit
messages, or technical documentation unless the user is explicitly drafting one
of the communication types above.

## Start With the Reader

Before writing, identify:

1. Who is receiving this?
2. Why does it matter to them?
3. What should they understand, decide, or do?

Write for the reader's context, not the sender's sequence of discovery.

## Use the Adaptive Reader Journey

Order the message around the questions that occur naturally in the reader's
mind:

1. **What:** What is this about?
2. **Why:** Why am I receiving this, and why does it matter to me?
3. **Consequence:** What changes or goes wrong if nothing is done?
4. **Reinforcement:** What evidence, observation, or context makes this credible?
5. **Action:** What should happen next, by whom, and when?

Adapt the structure to the message:

- Combine stages when one clear sentence can do the work.
- Omit consequence when there is no meaningful downside to state.
- Omit reinforcement when the message does not depend on evidence.
- For informational articles, action may be a takeaway, recommendation, or next
  step rather than a direct call to action.
- Never add filler merely to make all five stages visible.

## Pass the Six-Second Skim Test

The opening should let a scanning reader understand the subject and its
relevance in about six seconds.

Use the 50/72 pattern as a brevity heuristic:

- Aim to summarize the **what** in a subject or headline around 50 characters or
  fewer.
- If more context is needed, add no more than one or two short opening lines or
  bullets around 72 characters each.
- Use those lines to establish the **why**, immediate stakes, or requested
  action.
- Prefer clarity over counting. Exceed the guideline when essential terminology
  or accurate context requires it.
- Do not force the full message body to wrap at 72 characters.

The opening must not bury the point under greetings, background, chronology, or
throat-clearing.

## Adapt to the Channel

### Email

Use a specific subject, a bottom-line opening, only the context needed to
support it, and an explicit request or next step.

```text
Subject: [What has happened or needs attention]

[Why the recipient is involved and the immediate relevance.]
[Optional consequence or requested timing.]

[Evidence or essential context.]
[Action, owner, and deadline.]
```

Illustrative shape:

```text
Subject: Audit logs are missing

Fourteen production requests lack the expected audit events.
This may leave the release without complete compliance evidence.

The attached trace shows where event capture stopped.
Please confirm the recovery owner by 15:00 today.
```

### Workplace or Public Post

Lead with a concrete headline or hook. Explain why the audience should care,
reinforce the claim with evidence where needed, and finish with a clear action
or useful takeaway.

```text
[Concrete headline]

[Why this matters to this audience.]
[Evidence or consequence, if relevant.]
[Call to action, recommendation, or next step.]
```

Illustrative shape:

```text
API certificate expires Friday

Production calls will fail if the certificate is not renewed.
Monitoring confirms that the replacement is not deployed.
Service owners: complete the renewal by Thursday.
```

### Threads and Work Item Comments

Lead with the decision, status, or requested action. Include only the context
needed for the recipient to understand the impact, then state the next owner or
response needed. Reply directly to the point being discussed; use bullets when
they make multiple decisions or actions easier to scan.

```text
[Decision, status, or request.]

[Essential supporting context or evidence.]
[Owner and next action, if applicable.]
```

### Article

Use a compact title and a one- or two-line standfirst that communicates the
what and why before expanding into the full argument.

```text
[Compact title]

[What the article establishes and why it matters.]
[Optional consequence, finding, or reader benefit.]

[Evidence-led body.]
[Takeaway, recommendation, or next step.]
```

Illustrative shape:

```text
Why audit evidence needs context

Logs can prove an event occurred, but not always why it happened.
Context turns records into evidence people can act on.

[Evidence-led body.]
[Takeaway or recommendation.]
```

Examples demonstrate structure only. Replace every fact, consequence, owner,
and deadline with verified source information.

## Keep the Message Credible

- Match urgency to the supplied facts; do not dramatize routine information.
- Separate verified evidence from interpretation or prediction.
- State consequences only when they are plausible and relevant.
- Preserve important qualifications instead of shortening a claim until it
  becomes misleading.
- Use concrete nouns, active voice, short paragraphs, and direct requests.
- Remove background that does not change the reader's understanding or action.

## Pre-Delivery Check

- Can the reader identify the what and why from the opening?
- Does the opening pass the six-second skim test?
- Is the subject or headline concise, with no more than two short context lines?
- Are the consequence and urgency proportionate to the facts?
- Is reinforcement based on supplied evidence rather than invention?
- Is the next action, recommendation, or takeaway clear?
- Can anything be removed without losing meaning?

## Final Rules (Anchor)

1. Lead with what matters and why it matters to this reader.
2. Use consequence and reinforcement only when they are factual and useful.
3. End with a clear action, recommendation, next step, or takeaway.
4. Treat 50/72 as a brevity heuristic and clarity as the higher priority.
5. Make the opening useful within a six-second skim.
> If anything above conflicts with these, **these win**.

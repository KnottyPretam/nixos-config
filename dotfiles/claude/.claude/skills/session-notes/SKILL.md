---
name: session-notes
description: >-
  Distil this session into a handoff note in the Obsidian claude-sessions vault,
  and — when this session pushed a pull request — a change note for it in the
  project's scr_notes vault, then hand off to /compact. Use when the user asks to
  save, capture, checkpoint or write up the session, wants the context window
  dumped to a note before compacting, says the window is filling and they want it
  preserved first, or asks to write up the PR that was just pushed.
allowed-tools: Bash(mkdir*) Bash(date*) Bash(head*) Bash(ls*) Bash(stat*) Bash(basename*) Bash(git rev-parse*) Bash(git symbolic-ref*) Bash(git remote*) Bash(git reflog*) Bash(git log*) Bash(git diff*) Bash(git merge-base*) Bash(/home/pchoudhury/.claude/forgejo-get.sh:*) Bash(git -C /home/pchoudhury/obsidian_vaults/tiberius add:*) Bash(git -C /home/pchoudhury/obsidian_vaults/tiberius commit:*) Bash(git -C /home/pchoudhury/obsidian_vaults/tiberius push:*) Bash(git -C /home/pchoudhury/obsidian_vaults/tiberius pull:*) Bash(git -C /home/pchoudhury/obsidian_vaults/tiberius status:*) Read Write Edit
---

# Session notes

Write what this session knows into one markdown note in the Obsidian vault, so
the context window can be compacted without losing it. Then, only if this
session pushed a pull request, write a change note for that PR as well.

Target directory — from `~/.claude/CLAUDE.md` §5, "Claude Sessions":

```
${HOME}/obsidian_vaults/tiberius/claude-sessions
```

Write **from your own memory of the conversation**. Do not read the session
transcript JSONL to reconstruct it: the format changes between releases, and
pulling a multi-megabyte transcript into context to save context defeats the
purpose. The only thing worth reading from it is the session name, one line, in
step 1.

## Step 1 — resolve the filename

`<session name>_<one-to-three-word description>_<date>.md`

```sh
DIR="${HOME}/obsidian_vaults/tiberius/claude-sessions"
mkdir -p "$DIR"

SLUG=$(pwd | sed 's|/|-|g')
TRANSCRIPT="${HOME}/.claude/projects/${SLUG}/${CLAUDE_SESSION_ID}.jsonl"
NAME=$(head -1 "$TRANSCRIPT" 2>/dev/null \
       | python3 -c "import json,sys;print(json.load(sys.stdin).get('customTitle',''))" 2>/dev/null)
[ -z "$NAME" ] && NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
DATE=$(date +%F)
```

- **Session name** — the title set by `/rename`, which lives as `customTitle` on
  the transcript's first line. `head -1` costs one line. This field is
  undocumented and may break on a release, hence the fallback to the repository
  directory name — which is usually the same string anyway.
- **Description** — you choose it: one to three lowercase words, hyphen
  separated, naming what the session was actually about. `wiki-build`,
  `nav-rework`, `cgc-index-repair`. Not `session-summary` or `work`.
- **Date** — ISO `YYYY-MM-DD`.

Giving `steel-base_wiki-build_2026-08-24.md`.

## Step 2 — update, do not duplicate

```sh
ls "$DIR/${NAME}"_*_"${DATE}".md 2>/dev/null
```

If that matches a file, **rewrite that file, keeping its existing name**, folding
in everything that has happened since it was written. One note per session per
day. Only create a new file when nothing matches.

## Step 3 — write the note

Match the vault's house style: frontmatter, an H1, a metadata bullet, numbered
sections.

```markdown
---
title: "<Session> — <description>"
date: <YYYY-MM-DD>
tags: [claude-session, <repo>]
---

# <Session> — <description>

- **Session:** `<name>` · **Date:** <YYYY-MM-DD> · **Repo:** `<path>` @ `<sha>`

## 1. What this session set out to do
## 2. What was done, and verified
## 3. Decisions taken, and why
## 4. Findings worth keeping
## 5. Open threads and next steps
## 6. Key paths
```

What earns a place:

- **Prefer what cannot be re-derived.** The repo, its git log and its own docs
  already hold the code. Record the reasoning, the dead ends, the things that
  turned out to be wrong — those exist nowhere else once the window is gone.
- **Decisions carry their reason.** "Chose X" is nearly useless in a month;
  "chose X because Y ruled out Z" survives.
- **Separate verified from assumed.** If something was checked, say how. If it
  was inferred and never confirmed, mark it — an unmarked guess reads as fact
  later.
- **Open threads must be actionable** — what is blocked, on what, and what the
  next concrete step is. This is the section a resuming session reads first.
- **Corrections are findings.** If a claim made mid-session was later shown
  wrong, record the correction, not just the conclusion.
- **Compact, not exhaustive.** A handoff, not a transcript. Drop anything that
  was merely process.

If step 4 finds a PR, add its note's path to §6 in this same pass — one write, by
the rule in step 2.

**When the PR note is asked for on its own** — a later turn, or a session whose
note is already written — step 3 has already run. Make exactly one edit to §6 to
add the link, guarded on the link not already being there. That is the only case
in which this file is touched twice, and the guard is what keeps a re-run from
duplicating the row.

## Step 4 — did *this session* push a pull request?

Runs after the session note is written, so nothing here can cost the user their
handoff note. **Every gate is a silent skip on failure.** Batch them into one call.

```sh
BR=$(git symbolic-ref -q --short HEAD)                      # detached HEAD -> skip
UP=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)   # no upstream -> skip
BASE=$(git symbolic-ref -q --short refs/remotes/origin/HEAD | sed 's|^origin/||')
[ -z "$BASE" ] && BASE=main           # origin/HEAD is a local ref and may be absent
SLUG=$(git remote get-url origin | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#')

PUSH=$(git reflog show --date=unix "$UP" \
       | grep 'update by push' | head -1 | sed -E 's/.*@\{([0-9]+)\}.*/\1/')
START=$(stat -c %W "$TRANSCRIPT")      # 0 on a filesystem without birth times
```

`git symbolic-ref`, not `rev-parse --abbrev-ref`: the latter returns the literal
string `HEAD` when detached, and that will cheerfully be sent to the API.

**The recency gate — `$PUSH` must be ≥ `$START`.** A push predating this session
is not this session's push. Without this the skill misfires forever: a merged
PR's branch left checked out still has an upstream and a push reflog entry, so
every later session in that tree would rewrite the note. If `$START` is 0, take
the first `timestamp` in the first twenty transcript lines; if that fails too,
skip rather than guess. No `update by push` entry means "no push recorded in this
clone" — not "never pushed", but skip either way.

Then one memory gate: **you must remember making that push.** Git confirms it; it
cannot establish it.

One API call, **redirected to a file — never piped**, since `$?` reads 0 through
a pipe and a 404 becomes an empty object and then fiction:

```sh
/home/pchoudhury/.claude/forgejo-get.sh "repos/$SLUG/pulls/$BASE/$BR" > "$tmp" 2>/dev/null
[ -s "$tmp" ] || skip
```

**Never the `/pulls` list endpoint** — it paginates and times out, with
`state=open` as well as `state=all`; `pulls/{base}/{head}` answers in half a
second. Nor `issues?type=pulls`, which returns an incomplete set.

**If the PR reports `merged: true`, cross-check the number against git:**

```sh
git log origin/"$BASE" --merges --format='%s' | grep -F " from $BR into " | head -1
```

A reused branch returns the **wrong PR** — the endpoint answers with the older
one and both share a head sha, so no sha check catches it. Take the `(#N)` from
that subject; on disagreement the merge commit wins and the note says two PRs
shared the head ref. Several distinct `#N` — stop and ask.

**An empty result is not a disagreement.** If the merge landed after this clone
last fetched, `origin/$BASE` still predates it and the grep finds nothing. Check
whether `origin/$BASE` equals the PR's `merge_base`; if it does, the clone simply
has not seen the merge. Keep the API's number, and say in the note that it is not
corroborated by a local merge commit. You may not `git fetch` to settle it.

Locate the folder: the repo directory name up to its first `-`, plus `-scr_notes`
(`steel-update` → `steel-scr_notes`). **Absent → skip**; creating a vault folder
is not this skill's call.

Confirm in one line before writing, naming both candidates if the number is
ambiguous. One question, not two. Note that `allowed-tools` restricts rather than
grants — only `forgejo-get.sh` is allowlisted, so the git probes will prompt;
that is expected, and if a prompt is declined, drop the PR note and go to step 6.

## Step 5 — write the PR change note

`<scr-dir>/pr<N>_<slug>_change_note.md`.

> **You may write only paths matching `pr[0-9]+_*.md` in that directory.** No
> hand-written note matches that pattern, so "never touch a note I did not write"
> needs no judgement at write time. Glob `pr<N>_*.md` first: one match, rewrite
> it; two or more, stop and ask.

```yaml
---
title: "Change Note: <PR title, verbatim>"
date: <YYYY-MM-DD>
tags: [scr-notes, change-note, generated]
source: <PR html_url>
---
```

**Read `<scr-dir>/simulation_bus_change_note.md` and follow it** — an exemplar
cannot drift from house style the way a template copied in here would. Sections,
in order: *What was asked* · *The headline result* · *The phases* · *Since the
previous push* · *Verification* · *Open items* · *Files changed* · *Commits* ·
*Related notes*.

Four things one read may not make obvious: callout types are **lowercase** and
the seven in use are `abstract failure info question success summary warning`
(`note` is not one); diffstats use U+2212 for the minus; `file:line` citations
are kept here though the wiki dropped them; links are **relative markdown**,
`[label](other_note.md)`, not `[[wikilinks]]`.

**Headline numbers come from the API** — `merge_base`, `changed_files`,
`additions`, `deletions`. Not `base.sha`, which is the base *tip* and a trap.
Cross-check against `git diff --shortstat <merge_base>...<head>`; on mismatch
report both and say the remote-tracking ref is stale. You may not `git fetch` to
resolve it, and skip the local half on a shallow clone.

**Since the previous push** has three outcomes, and the last two are different
facts. First push (oldest reflog entry's old value is all zeros) — omit. Previous
head known — write it, titled with the date and both shas, and say it covers the
latest push only; earlier deltas are not accumulated. Not in this clone's reflog
— omit, and say so in one line.

**Verification is a bare `| Check | Result |` table with no pre-filled rows.**
Write a row **only** if this session ran that check and you remember the result.
A file under `build/` is **not evidence** — it carries no commit stamp and may
predate the head being documented. Anything not run is `**not run this session**`,
which is a real answer.

CI rows come from `repos/$SLUG/commits/<sha>/status`: the contexts, their
verdicts, and the `description` quoted verbatim — it carries the duration, so
never compute one from timestamps. Say once that the runner's log text is not
retrievable through the API, so per-test counts are local.

**Related notes** — read the other notes' titles and open items and judge. Look
for an item the PR advances or closes, not shared vocabulary: keyword overlap
finds nothing or everything. **Zero is a valid answer**; say so rather than
reaching.

No handling banner. The `> [!warning]` blocks in the existing notes are
situational, not boilerplate, and stamping a marking claim you cannot
substantiate over-marks the note and stops it being read. One line saying the
note was generated is enough.

## Step 6 — commit and push the vault

Runs after step 5 so the session note and the PR note land in one commit.

**Write the vault path out in full at every call site. Never
`git -C "$VAULT" …`.** Permission patterns are matched against the command as
literally written, so a variable does not match the allowlist and every call
falls back to a prompt — which defeats the point of the step. Each command is
its own Bash call: a chained `&&` is checked per segment and hides which half
failed.

```sh
git -C /home/pchoudhury/obsidian_vaults/tiberius add -- <note> [<pr-note>]
git -C /home/pchoudhury/obsidian_vaults/tiberius status -sb -- <note> [<pr-note>]
git -C /home/pchoudhury/obsidian_vaults/tiberius commit -m "<message>"
git -C /home/pchoudhury/obsidian_vaults/tiberius push
```

**Stage only the files this skill wrote**, as explicit pathspecs after `--`.
Never `git add -A`, never `git add .`. The vault is a live Obsidian working
tree and may hold half-finished edits that are not yours to commit.

**The session's own repository is never touched.** The working directory is
normally a project repo; every command here carries `-C` to the vault precisely
so no project repo is ever staged, committed or pushed by this skill.

**Message style follows the vault's own log** — one plain sentence, sentence
case, no `docs:`-style prefix and no body:

- `Add session note for steel-update sil-main-refactor`
- `Update session note for steel-update sil-main-refactor` — when step 2 rewrote
  an existing note rather than creating one
- `Add session note and PR #144 change note for steel-update` — when step 5 ran

**Nothing to commit is success, not failure.** A re-run producing byte-identical
notes makes `git commit` exit non-zero saying *nothing to commit*. Skip the
commit and still attempt the push: that is what heals an earlier run which
committed but failed to push.

**If the push is rejected**, another session reached the vault first. Rebase and
push once more — `--autostash` because the working tree may be dirty:

```sh
git -C /home/pchoudhury/obsidian_vaults/tiberius pull --rebase --autostash
git -C /home/pchoudhury/obsidian_vaults/tiberius push
```

One retry, not a loop.

**The push publishes the whole branch, not just this commit.** Read the
`## main...origin/main [ahead N]` line from `status -sb`; if N is greater than
one, say in step 7 how many commits went up and that only one of them is this
skill's.

**On failure: report, and stop.** A push still rejected after the retry, a
rebase conflict, a vault that is not a git repo, or one with no remote — state
the reason and the exact command to finish by hand, and **do not proceed to step
7**. The notes are on disk and, in the push case, committed locally, so nothing
is lost; but a failure must not be buried under an instruction to compact.

## Step 7 — hand off to `/compact`

State the path or paths written and the commit result, then tell the user to run
`/compact` — with a focus argument drawn from §5's open threads, since
`/compact` accepts one:

> Written to `<path>`. Committed and pushed (`<sha>`). Run `/compact focus on
> <the open threads>` to free the window — I can't run it myself; `/compact` is
> a built-in the model cannot invoke.

Say that in one line. Do not pad it, and do not offer to run it.

## What this skill does not do

- **It does not run `/compact`.** Not possible: the Skill tool reaches `/init`
  and `/security-review`, not `/compact`, and no hook can start a compaction —
  `PreCompact` only fires once one is already underway, and can only block it.
- It does not parse the transcript beyond the first line, except to recover a
  session-start timestamp when the filesystem has no birth time.
- It does not touch `MEMORY.md` or `steel-wiki/`. Those are separate
  destinations with separate purposes, and the wiki's index is hand-written.
- **It never edits a note it did not write.** In the scr_notes directory it may
  write only `pr[0-9]+_*.md`.
- **It never commits or pushes the repository the session is working in.** Only
  the vault, and only by explicit `-C`.
- It stages only the note files it wrote. Unrelated edits in the vault working
  tree are left alone, uncommitted.
- It does not resolve a rebase conflict. One `--rebase --autostash` retry, then
  it stops and hands the command back.
- It never builds, or runs a test suite, to manufacture evidence for a note.
- It cannot quote CI log text — no endpoint serves it.
- It never opens, updates, merges or comments on a pull request. It reads one.
- It will not write up a PR this session did not push.

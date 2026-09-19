---
name: cgc-refresh
description: >-
  Refresh, rebuild or create the CodeGraphContext (cgc) code-graph index for the
  repository the session is currently in. Use when the user says the code index
  or code graph is stale, asks to reindex/re-index/refresh/rebuild/update the
  cgc index or graph, asks to index this repo with cgc, or after a large merge,
  branch switch or restructure has moved enough code that graph queries would be
  answering from a stale picture. Also covers diagnosing cgc failures —
  database lock contention, unreachable database, a repo that was never indexed.
---

# Refresh the cgc index for the current repo

`cgc` is CodeGraphContext: it parses a repository into a code graph (functions,
classes, calls, imports) held in a local database, and serves it over MCP. The
graph only reflects the code as of the last index, so it goes stale silently —
queries keep answering, just from an old tree.

## The one command

```sh
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cgc update "$ROOT"
```

**`cgc update` is idempotent and covers both cases** — never-indexed and
already-indexed. Do not write list-then-branch logic around it.

Worth knowing *why*, because the name is misleading. `update` is an alias for
`reindex_helper`, whose own docstring is *"Force re-index by deleting and
rebuilding the repository"*. It checks whether the path is already indexed; if
so it deletes that index first, then indexes from scratch either way. So:

- it is **not** incremental — cost scales with the whole repo, not the diff;
- it works fine on a repo that was never indexed (the delete is simply skipped);
- `cgc index --force` does the same thing under a different verb.

For a first-ever index `cgc index "$ROOT" --summarize` is the honest verb and
prints what landed. After that, `update` is the one to reach for.

## Always pass the root explicitly

`cgc` defaults to the current directory. Invoked from a subdirectory it will
index that subtree and register it as its own repository — which looks like it
worked. Resolve the root first, as above, and fall back to `pwd` for
non-git directories.

## Verify, don't assume

```sh
cgc list                # the path should appear, under the name you expect
cgc stats "$ROOT"       # non-zero files / functions / relationships
```

An index that silently covered nothing still exits 0.

## Failure modes, by symptom

**`Could not set lock on file ... /db/kuzudb`, after retries.**
KùzuDB is single-writer and another `cgc` process holds it. This is common with
several Claude sessions open on the same machine — check with
`ps -eo pid,etime,cmd | grep '[c]gc'`. **Wait for it; do not kill the other
process and do not switch backend to get around it** — a different backend means
a different graph, and the two then disagree. Poll until the PID exits, then run.

**`Database Connection Error` / services fail to initialise.**
Run `cgc doctor`. The active backend and its path come from
`~/.codegraphcontext/.env` (`DEFAULT_DATABASE`, plus `KUZUDB_PATH` /
`FALKORDB_PATH`). That file can change between sessions, so confirm which backend
is live rather than assuming — the first line of any cgc command prints it.

**`cgc: command not found`.** Installed via pipx; the shim is `~/.local/bin/cgc`.
Check `~/.local/bin` is on PATH before concluding it is missing.

## Two hygiene notes

**cgc writes `.cgcignore` into the repo root** on first index. It is untracked,
and most repos' `.gitignore` does not match it — so it is one `git add -A` from
being committed. Leave it untracked and say so; put patterns that apply to every
repo in `~/.codegraphcontext/global/.cgcignore` instead, where nothing lands in a
working tree. Note the global defaults cover `build/` but not sibling trees like
`build-debug/`, so add `build-*/` if the project uses them.

**`cgc report` writes `CGC_REPORT.md` into the repo**, not into the cgc config
directory. Same consideration.

## Noise you can ignore

Indexing emits `[SECRETS] N potential secret(s) detected in <file>` lines. That
is an entropy heuristic firing on ordinary source — class and function bodies —
not a finding. It matters only in that the source text is stored verbatim in the
graph, which is what the tool is for. Set `REDACT_SECRETS=true` in the `.env` if
that is not wanted for a given codebase.

## Adjacent commands

| | |
|---|---|
| `cgc list` | every indexed repository |
| `cgc stats [path]` | per-repo, or overall with no path |
| `cgc delete <path>` | drop a repository from the graph |
| `cgc clean` | remove orphaned nodes (needs `ALLOW_DB_DELETION=true`) |
| `cgc hook install` | git hooks that call `update` after commit and checkout — the automatic alternative to running this by hand |
| `cgc watch` | continuous refresh on file change |
| `cgc report` | writes `CGC_REPORT.md` — see above |

## Contexts

`cgc` supports named contexts (logical workspaces), selected with `--context`.
Check `cgc context list`; if the mode is `global` with none defined — the usual
case — omit `--context` entirely. This is what the `Resolving context...` line in
every command's output refers to.

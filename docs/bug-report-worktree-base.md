# Bug report — Agent `isolation: "worktree"` bases the worktree on `origin/HEAD`, not the active branch's HEAD

> Draft to file at `github.com/anthropics/claude-code/issues` (or via `/bug` in the CLI). Written in English
> for the maintainers. Discovered 2026-07-14 while running fan-out agents in a mid-migration repo.

## Environment
- **Claude Code:** 2.1.209
- **OS:** macOS (darwin)
- **Tool:** `Agent` with `isolation: "worktree"` (fan-out / parallel sub-agents)

## Summary
When a sub-agent is spawned with `isolation: "worktree"`, the temporary git worktree is created based on
**`origin/HEAD`** (i.e. the remote's default branch, effectively `origin/main`) instead of the **HEAD of the
branch currently checked out** in the repo. In any repo whose working branch has diverged from the remote
default branch, the agent is born on a stale tree and cannot find the files it is supposed to operate on.

## Expected behavior
A worktree created for an isolated agent should be based on the **currently checked-out commit/branch HEAD**
of the repo the agent is launched from (e.g. `git worktree add <path> HEAD`), so the agent sees exactly the
code the orchestrator is working on.

## Actual behavior
The worktree is based on `origin/HEAD` (→ `origin/main`). The agent's tree reflects the remote default branch,
not the active branch. When `main` is release-only and the real work lives on `develop`/feature branches, the
agent lands on an old commit.

## Reproduction
1. In a repo where the active branch has commits **not** present on `origin/main` (e.g. `main` is release-only
   and current work lives on `develop`/a feature branch — a very common flow).
2. Spawn a sub-agent with `isolation: "worktree"`.
3. Have the agent inspect its own tree (`git rev-parse HEAD`, `git ls-tree --name-only HEAD`, `git status`).
4. Observe: the agent's HEAD equals `origin/main`, **not** the branch that was active when it was spawned.

## Evidence (real repo, 4 independent agents, same batch — all born at the same stale commit)
Repo: a .NET app mid-migration from a monolith (`cpscsmWasm/`) to a homologated multi-project layout
(`cps.blazorwasm/`, `cps.domain/`, …). Verified refs:

```
origin/HEAD  -> bfc127e2   (symbolic-ref: refs/remotes/origin/main)   tree: cpscsmWasm/   (PRE-migration monolith)
origin/main  -> bfc127e2   (same)                                     tree: cpscsmWasm/
main (local) -> 0a5cd766                                              tree: cpscsmWasm/   (also pre-migration)
HEAD (active branch: fix/cockpit-...) -> 3239b2db                     tree: cps.blazorwasm/ cps.domain/ …  (MIGRATED)
origin/develop -> a78b8cbd
```

All 4 agents reported being born at `bfc127e2` ("hotfix boton", 2025-11-28) — i.e. on the pre-migration
monolith — instead of `3239b2db` (the active branch). They only recovered by self-detecting the wrong tree
and running `git reset --hard <target-branch>` on their own isolated branch.

## Root cause
The worktree base is resolved from `origin/HEAD` (the remote default branch) rather than the repo's current
checked-out HEAD. This is masked in repos where `origin/main` tracks the working state, but surfaces whenever
the active branch has diverged from the remote default — the mainstream case for any "`main` is release-only,
work on `develop`" workflow. Here the migration was never promoted to `main`, so `origin/main`/`origin/HEAD`
still point at the old monolith and every worktree is created there.

## Impact
Beyond the correctness bug, this has a **behavioral cost that discourages using isolated agents at all**:
every fan-out cycle pays a tax (each agent must detect the wrong tree, `git reset --hard`, and re-verify), so
the rational default becomes "just do it serially in the main tree" — which defeats the purpose of worktree
isolation and parallel fan-out. It also trips `reset --hard`-detecting safety hooks with false positives.

## Suggested fix
Base the isolated worktree on the **currently checked-out HEAD** (`git worktree add <path> HEAD`, or the SHA of
the active branch), not on `origin/HEAD` / the remote default branch.

## Workaround (until fixed)
Instruct each isolated agent, at the very start of its turn, to `git reset --hard <target-branch>` inside its
own (isolated) worktree so it lands on the correct base. Safe because it operates on the agent's isolated
branch, never the shared tree. (This is what our agents ended up doing organically.)

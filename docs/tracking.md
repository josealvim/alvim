# Tracking slices

The roadmap is tracked entirely in GitHub so progress is visible without reading
the code.

## Structure

- **Milestone** = phase (`Phase 1 — Walking skeleton`, ...).
- **Issue** = one vertical slice, prefixed `S01 — ...`, labeled `slice` plus area
  labels.
- **Task list** = the slice's subtasks, as checkboxes inside the issue.
- **`docs/design.md`** = the decisions the slice must respect.
- **`docs/roadmap.md`** = the dependency-ordered map and issue links.

A slice is the unit of work. Do not split an issue into ad-hoc sub-issues; check
off the task list instead. If a slice is too big, split it in `roadmap.md` and
create two issues that each remain runnable and tested.

## Slice lifecycle

1. Pick the next unblocked slice (all dependencies closed).
2. Create a branch: `slice/sNN-short-name`.
3. Implement the subtasks, checking them off in the issue as they land.
4. Keep the slice runnable at every commit; no dead scaffolding.
5. Add/update tests with the behavior, not after the phase.
6. Run `make test`, plus ASan/UBSan when the slice touches memory or threading.
7. Open a PR with `Closes #<slice>` and a short demo description (keys to press,
   what to see).
8. Merge, close the issue, and update any decision that changed in
   `docs/design.md`.

## Definition of done

A slice is done when:

- [ ] The demo in the issue works in the real terminal.
- [ ] New behavior has unit and/or headless grid tests (`make test` green).
- [ ] No unowned TODOs, dead code, or scaffolding left behind.
- [ ] Public seams still match `docs/design.md`; deviations are documented.
- [ ] Error paths (missing file, bad input, OOM/EIO where relevant) do not crash
      or corrupt terminal state.
- [ ] The next slice's dependencies are satisfied.

## Labels

| Label | Meaning |
| --- | --- |
| `slice` | A roadmap slice |
| `terminal` | Terminal driver, ANSI, input decoding, signals |
| `buffer` | Piece table, editing operations, undo |
| `input` | Input model, keymaps, modes |
| `vim` | Vim grammar behavior |
| `ui` | Screen, renderer, chrome, overlays, mouse |
| `workspace` | Tabs, panes, file tree, buffers |
| `search` | In-buffer or project search |
| `syntax` | Tree-sitter and grammar plugins |
| `git` | libgit2, status, diff |
| `persistence` | Session, snapshots, file watching |
| `advanced` | Multi-caret, macros, completion |
| `infra` | Workers, queues, build integration |
| `perf` | Performance and hardening |
| `docs` | Documentation and release |

Sizes are `S`, `M`, `L` in `roadmap.md` (roughly a session, a day, or a couple of
days — not commitments).

## Changing the plan

When a decision changes:

1. Update `docs/design.md`.
2. Update the affected issue bodies/task lists and dependencies.
3. Update `docs/roadmap.md` (including the Mermaid graph) if ordering changes.
4. Note the change in the issue or PR that caused it.

## Project board (optional)

If the GitHub CLI has the `project` scope, a board named **alvim roadmap** mirrors
these issues. Without the scope, milestones plus the roadmap table are the source
of truth. To enable the board:

```sh
gh auth refresh -s project
```

Then add the repo issues to a Project v2 with `Status` and `Phase` fields.

# alvim

A small, hackable, vim-shaped terminal editor for code and prose.

`alvim` is a Linux-only, single-binary editor written in C17. It aims to be
small enough to understand fully and easy to modify for personal workflows,
while still being a real daily driver: modal editing, tabs and splits, a file
tree, project search, tree-sitter highlighting, live diffs, multi-caret, and
macros.

**Status:** design + scaffold. The implementation is planned as vertical,
testable slices tracked in GitHub milestones and issues.

- Project board: [alvim roadmap](https://github.com/users/josealvim/projects/1)
- Pinned tracker: [#27 — Roadmap tracker](https://github.com/josealvim/alvim/issues/27)
- Slice map: [`docs/roadmap.md`](docs/roadmap.md)

## Design

- [`docs/design.md`](docs/design.md) — architecture, locked decisions, scope,
  assumptions, and risks.
- [`docs/roadmap.md`](docs/roadmap.md) — phases, slice dependency graph, and
  issue links.
- [`docs/tracking.md`](docs/tracking.md) — how slices, subtasks, and reviews are
  tracked.

## Non-goals

LSP, an integrated terminal, a debugger, a general plugin ABI, remote/SSH
editing, file-tree mutations, format-on-save, and Windows/macOS support are out
of scope. Grammar plugins are the only dynamic extension point.

## Build

Requirements: Linux, a C17 compiler (`gcc` or `clang`), `make`, and
[`depi`](https://github.com/josealvim/depi) for dependency generation.

```sh
make
./targets/editor.out
make test
```

The build layout is:

- `sources/` — editor sources and headers
- `targets/` — program and test entry points (`targets/editor.c`,
  `targets/tests/`)
- `vendor/` — vendored third-party code

Vendored dependencies (once the relevant slices land): `stb_ds`, `utf8proc`, the
tree-sitter runtime, and a prebuilt static `libgit2`.

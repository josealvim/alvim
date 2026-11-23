# alvim — design

This document is the shared understanding reached before implementation. It is
the reference for the slices in [`roadmap.md`](roadmap.md). When a decision
changes, update this file and the affected issues together.

## 1. Identity

`alvim` is a Linux-only, single-binary, C17 terminal editor built with the
existing POSIX `makefile` + `depi` setup. It is a personal daily driver for code
and prose: vim-shaped, small enough to understand fully, and hackable by editing
C.

"Small" means one coherent codebase with clear seams, not few features. The
feature surface is deliberately focused; the architecture is expected to carry
it without special-case sprawl.

### In scope

- Modal vim-style editing with a core grammar subset
- Tabs, splittable panes, shared buffers
- Keyboard-first file tree (navigation only)
- In-buffer and project-wide search
- Tree-sitter syntax highlighting via dynamic grammar plugins
- Live diff gutters and a side-by-side diff pane
- Session restore and crash snapshots
- True multi-caret editing and macros
- Full mouse UI
- Vim-ish `:` subset plus a command palette
- Word, path, and command completion
- Basic autoindent and indentation detection
- Truecolor with 256/16-color fallback and small overlays

### Explicit non-goals

- LSP, completion protocols, diagnostics (decoration layer stays reusable)
- Integrated terminal, debugger, REPL
- General plugin ABI; grammar `.so` plugins are the only extension point
- Remote/SSH editing, collaboration
- File-tree mutations (create/rename/delete); tree is navigation-only
- Format-on-save / external formatters
- Folds, marks, jump list, named yank registers
- Persistent undo across sessions
- macOS, BSD, Windows

## 2. Architecture overview

Request/action flow:

```
terminal driver (raw ANSI/xterm)
  -> decoded key events
  -> input model (vim grammar subset; macro replay)
  -> named commands + arguments
  -> editor core (buffers, views, layout)
  -> renderer (cell grid)
  -> terminal driver
```

Async work runs beside this flow:

```
worker pool            parse workers          git worker           inotify thread
(file tree, search)    (per-buffer trees)     (libgit2, own repo)  (watched files)
        \                    |                      |                    /
         +---- bounded queues, cancellation, generation-tagged results ----+
                              (stale results are dropped, never applied)
```

### Seams

- **Terminal driver** — vtable; ANSI/xterm implementation for the real terminal,
  fake in-memory driver for tests. All layout and view code sees only a cell
  grid.
- **Input model** — consumes decoded keys and emits named commands with
  arguments. The vim grammar is one implementation of this seam; keymaps are
  compile-time C. Macros record at this boundary and replay through it.
- **Command registry** — every user-visible action is a named command with docs
  and an argument shape. Keymaps, ex aliases, and the palette all dispatch
  through it; internal callers use the same path.
- **View interface** — panes own a view with a small vtable (`render`,
  `handle_command`, cursor/selection, scroll). Implementations: text, file tree,
  diff, search results.
- **Job executor** — worker pool API with cancellation and generations. Tests
  inject a synchronous executor.

## 3. Core models

### Composition

`tab page -> layout tree -> panes -> views`

- A buffer is a text document. A **view** is a cursor/scroll/selection state over
  a buffer. Several views (even in different panes/tabs) may show one buffer.
- Tabs own a splittable layout tree; tools are normal panes in that tree.
- File tree, diff, and search results are view implementations, not special
  cases in the layout code.

### Text buffer

- Piece table: immutable original file data plus append-only edit data; the
  document is a sequence of pieces.
- The append store is **chunked and stable** (never reallocates existing bytes),
  so snapshots shared with workers and undo remain valid.
- Line mapping and byte<->line/col conversion live in the buffer module.
- Loaded files are UTF-8. Display width uses `utf8proc`; full grapheme clusters
  are the cursor and selection unit. Bytes are never split mid-cluster.
- Files containing NUL bytes are refused with a message. Files above ~50 MB open
  with a warning and highlighting disabled.

### Undo

- Snapshot undo per undo group: a completed command, or a coalesced typing/delete
  run. Text bytes are shared, so snapshots are cheap.
- Redo is a second stack. Undo covers multi-caret edits atomically.
- No persistent undo in v1; crash snapshots cover unsaved work.

### Cursors and selections

- A view owns an ordered set of carets. Each caret may own a selection.
- Motions move all carets. Edit/operator commands apply per caret in document
  order, ranges merge on overlap, and the whole application is one undo group.
- Visual char/line/block modes are built on the same selection primitive.
- Default keys are leader-based so vim bindings stay intact: `<Space>n` /
  `<Space>N` add the next/previous occurrence of the word or selection,
  `Ctrl-Alt-Up/Down` stack carets, and `Esc` collapses to the primary caret.
  Alt-click (added by the mouse slice) also adds a caret. `Ctrl-D` remains
  vim's scroll-half-page. All bindings are compile-time remappable.

## 4. Input, commands, and editing

### Vim subset (first implementation)

- Modes: normal, insert, replace, visual (char/line/block), operator-pending,
  command-line.
- Verbs: `d c y p P > < J x s r`.
- Motions: `h j k l w W b B e E 0 ^ $ gg G f F t T % { } ( )` plus `/ ? n N`,
  counts, and page motions.
- Text objects: `iw aw i( a( i" a" ip ap`.
- Undo/redo and dot-repeat.
- Deferred: marks, folds, named yank registers, abbreviations.

### Ex and palette

- `:` prompt parses an optional range (`%`, line numbers, `'<,'>`), a command
  word, and arguments.
- Vim aliases for save/quit/edit/split/tab commands; `:s/pat/rep/[gi]` with
  POSIX ERE.
- Every registry command is reachable by name with fuzzy completion in a palette.
- No expression language, scripting, `:g`, or pipes.

### Registers and clipboard

- Unnamed register plus numbered delete/yank history.
- Lettered macro registers a-z; named yank registers remain deferred.
- System clipboard via OSC 52 with `xclip`/`wl-copy` fallback; bracketed paste.

### Macros

- Record decoded key events (code + modifiers + text) at the input-model
  boundary; replay feeds the same input model so grammar state and text entry
  behave exactly as typed.
- `q{letter}` starts/stops recording into macro register a-z; `@{letter}`
  replays, `@@` repeats the last macro, and counts are supported.
- Replay is cancellable, has a recursion guard, and shows a status indicator.
- Recording a macro never touches the yank registers.

### Indentation

- Detect tabs-vs-spaces and width per buffer; new files default to spaces, width
  4.
- Autoindent copies the previous line's indentation; simple dedent rules for
  `}`, `)`, `end`, `else`, `elif`, `case`.
- `>`/`<` shift ranges; no `=` operator and no formatter.

### Completion

- Insert-mode Ctrl-N/Ctrl-P completes words from open buffers.
- Path completion in file prompts; command-name completion in `:` and palette.
- No semantic/type-aware completion.

## 5. Terminal and UI

- Raw ANSI/xterm behind the driver seam: termios raw mode, alternate screen,
  cursor management, SGR mouse, bracketed paste, focus events, resize.
- Truecolor when advertised by the terminal, else 256 colors, else 16.
- Cell grid supports grapheme clusters, wide cells, fg/bg, and attributes with a
  diff-based flush.
- Chrome: tabline, per-pane statusline (mode, file, dirty, position, git branch,
  EOL), line-number/diff gutter, message line.
- Small overlay layer with rounded borders for completion, prompts, and
  confirmations; z-order and focus are part of the overlay API.
- Mouse: click focus/place caret, wheel scroll, drag select, double-click word,
  Alt-click add caret, cross-pane drag-select, tab drag/reorder, gutter line
  select, popup clicks. Shift+drag falls back to native terminal selection.
  Right-click context menus are deferred.
- Terminal state is restored on normal exit and on SIGINT/SIGTERM/SIGHUP.

## 6. Concurrency

- Worker threads are used from the first workspace feature (file tree scan); no
  "add threads later" rewrite.
- A bounded job queue with cancellation flags and generation/sequence numbers.
  Results carry their generation; the UI drops stale results.
- A dedicated git worker owns the only libgit2 repository handles (libgit2
  objects are not thread-safe).
- One parse worker per active buffer owns that buffer's tree-sitter tree.
  - The main thread appends ordered edit descriptors to a per-buffer log.
  - The worker incrementally reparses in edit order.
  - The worker publishes a read-only tree plus highlight ranges tagged with a
    generation; the UI reads the latest completed result.
- An inotify thread watches open files and relevant directories; events are
  coalesced and handed to the UI. mtime checks are the fallback.
- Shutdown drains or cancels jobs and joins threads without hangs or leaks.

## 7. Syntax highlighting

- Vendored tree-sitter runtime.
- Each grammar plugin is a `.so` exporting a versioned descriptor: language name,
  file extensions, `tree_sitter_<lang>()`, and highlight/injection query strings
  embedded as constants.
- The loader validates the ABI version and loads from compiled-in paths plus
  `$ALVIM_GRAMMAR_PATH`.
- Missing or broken grammars fall back to plain text; query errors are reported
  without breaking the buffer.
- Initial plugins: C, Markdown (with fenced-code injections), then Python, shell,
  JSON, YAML, TOML. Adding a grammar is a build rule plus a registry entry.

## 8. Git and diff

- Vendored **prebuilt static libgit2** plus headers; no CMake in this project's
  build. A rebuild recipe is documented separately; glibc coupling is accepted.
- All git access is read-only: repository discovery, branch/HEAD, status, blob
  reads.
- File tree shows git status decorations.
- Live diff gutters compare a buffer against a selectable baseline: on-disk file
  or `HEAD`. Diffs are computed on a worker, debounced, and generation-tagged;
  gutters mark added/changed/deleted lines.
- A side-by-side diff view compares a buffer with a revision/file, scroll-synced
  with aligned hunks; unified/side-by-side toggle.
- No staging, committing, or writing through git.

## 9. Persistence and file I/O

- Session state under `$XDG_STATE_HOME/alvim/` (fallback
  `~/.local/state/alvim`): versioned text format, atomic writes.
- Restores tabs, layout, open buffers, cursor/scroll, and active pane lazily.
  CLI file arguments override session restore.
- Dirty buffers get periodic crash snapshots; on startup a newer snapshot offers
  recover/discard. No vim swap files.
- Saves are atomic: same-directory temp file + rename, preserving mode. EOL style
  is detected per file and preserved for new lines. No trailing-whitespace
  trimming.
- External changes prompt to reload; unsaved edits are never silently discarded.

## 10. Configuration

- Compile-time C only (`config.c` or equivalent): options, keymaps, themes,
  grammar/plugin paths, indentation rules.
- No runtime config parser and no scripting host.
- Runtime state (session, crash snapshots) is machine-written and separate from
  configuration.

## 11. Build and dependencies

- Keep the existing POSIX `makefile` + `depi`; extend it with vendored objects,
  test targets, sanitizer targets, and grammar plugin rules.
- Vendored: `stb_ds` (already present), `utf8proc`, tree-sitter runtime, and a
  prebuilt static `libgit2` archive with headers.
- Grammar plugins build as `.so` from vendored generated parser sources; no CMake
  required.
- Linux-only: termios, poll, pthreads, inotify, dlopen, libgit2.

## 12. Testing

- Unit tests for pure modules: piece table, graphemes, vim grammar, command
  parsing, diff, ignore matching, session serialization.
- Headless integration harness: the real editor driven through the fake terminal
  driver with a synchronous job executor, asserting buffer state and rendered
  cell grids (golden frames).
- Synthetic mouse events and key sequences for UI behavior.
- ASan/UBSan targets; fuzz/property tests for piece table, graphemes, vim parser,
  and diff in the hardening slice.
- `make test` runs every `targets/tests/*.out`.

## 13. Performance

- Interactive target: source files up to ~50 MB, keystroke-to-render typically
  under ~16 ms, smooth scrolling on 10k+ line files, startup under ~100 ms with
  lazy restore, project search streaming first results within ~100 ms on a
  moderate repo.
- Degrade gracefully above the envelope: warn, disable highlighting, cap search
  file size; never block the UI.
- Snapshot undo needs coalescing and a memory cap for large files.

## 14. Defaults and assumptions

These are baked into the plan unless changed:

- Registers: unnamed + numbered yank/delete history; lettered macro registers
  a-z; named yank registers deferred.
- Clipboard: OSC 52, then `xclip`/`wl-copy`, then internal only.
- Search: POSIX ERE; incremental literal while typing, regex on commit; smartcase
  on.
- Project search skips hidden/binary/oversized files and respects `.gitignore`.
- Diff baseline: `HEAD` inside a repo, on-disk otherwise; toggle.
- Grammar paths: `$ALVIM_GRAMMAR_PATH`, `~/.local/lib/alvim/grammars`,
  `<exe_dir>/grammars`.
- Session state: `$XDG_STATE_HOME/alvim/session`, versioned text.
- Files with NUL bytes are refused; unwritable files are marked read-only.
- New files default to spaces/4; existing indentation is preserved.
- The repository may or may not be initialized with `git init`; the plan does not
  depend on it.

## 15. Risks

1. **Scope vs. size.** The feature list is large. Mitigation: strict seams, a
   single-file-editor milestone first, and slice-sized increments.
2. **Stable snapshots.** Worker parse trees and undo depend on the chunked append
   store; reallocating it would invalidate pointers. Must land before workers.
3. **Prebuilt libgit2.** glibc coupling is accepted; the archive and rebuild
   recipe need to be reproducible.
4. **Full mouse UI.** Hit-testing across panes, tabs, gutters, overlays, and
   cross-pane selection is stateful; land it after the workspace is stable.
5. **Grapheme × multi-caret × diff × macros.** Cursor invariants and undo
   atomicity are the likely bug clusters.
6. **Snapshot undo memory.** 50 MB buffers need coalescing and a cap.
7. **Tree-sitter plugin ABI.** Runtime/grammar version skew and query errors must
   degrade, not crash.

## 16. Deferred questions

- Named yank registers (macro registers are already lettered).
- Whether to add right-click context menus after the full mouse UI lands.

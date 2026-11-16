# Legacy branch reconciliation — 16 November 2026

Baseline: \`main\` at \`fe96b0c48d1b9cc829b3bf2629a743472efa24ed\`
(the two-parent merge of PR #6). Reconciliation performed using GitHub
branch comparisons, PR metadata and selected original/current source files.

## Outcome

**Do not merge any historical development branch wholesale.** A branch's
\`ahead_by\` count identifies commits absent from the graph, not necessarily
unimplemented behavior. The old branches diverged from much earlier code,
whereas PR #6 already introduced and verified newer Win32 W adapters and GUI
integration tests.

| Historical branch | Decision | Evidence |
| --- | --- | --- |
| \`feature/windows-build-and-packages\` (closed PR #2) | Superseded | VS2026 build/package manager and tests now live in \`main\`; old workflow scripts are earlier implementations |
| \`fix/long-path-phase-1\` (closed PR #3) | Superseded | Buffer/path helpers, release scripts and regression foundations are present in newer versions on \`main\` |
| \`fix/long-path-unicode-io\` (closed PR #4) | Superseded | Modern long-path APIs and tests in \`main\` use checked Unicode identities and bounded paths; do not overwrite with older adapters |
| \`bugfix/longandunicodefilenames\` | Selective extraction only | The original SHFileOperationA name-list construction uses a fixed buffer without bounding the two trailing NUL bytes on \`main\` |
| \`chore/visual-studio-2026-community\` (PR #1) | Already merged | PR #1 merged 13 November 2026; remaining branch divergence does not justify a second merge |
| \`feature/management-cli-main\` (PR #5) | Already merged | PR #5 merged 13 November 2026 |
| \`fix/unicode-longpaths-gui-regressions\` (PR #6) | Already merged | PR #6 merged 16 November 2026 and is an ancestor of \`main\` |
| Three \`milestone/gui-longpaths-*\` branches | Already contained | Compare against \`main\` reports zero commits ahead |
| \`chore/auto-label-pr-authors\` | Already contained | Compare against \`main\` reports zero commits ahead |
| Six \`copilot/*-comment-review\` branches | No runtime changes to port | One comment-translation commit each; two corresponding file blobs are identical to \`main\`, other comment wording differs |
| \`move-workflow-file\` | Reject | Contains a stub replacing a real GitHub Actions workflow; merging would regress CI |
| \`remove_zip-appnote_pk\` | Defer | Deletes a large ZIP specification file without a supported requirement to remove it |

## Selected safety fix from bugfix/longandunicodefilenames

**Problem:** \`src/worker.cpp\` contained two instances of:

\`\`\`cpp
char nameList[MAX_PATH + 1];
int l = (int)strlen(name) + 1;
memmove(nameList, name, l);
nameList[l] = 0;
\`\`\`

For a 260-byte path the final write is at index 261 of a 261-byte array.
A standalone AddressSanitizer reproduction of that original construction
reported a stack-buffer-overflow. The affected call sites are
\`DoDeleteFile\` and \`DoDeleteDir\`, before \`SHFileOperationA\`.

**Extracted:** \`src/common/shellfileopnames.h\` builds a single
double-NUL-terminated shell name only after verifying that the entire
path and both terminators fit. The worker returns a normal
\`ERROR_FILENAME_EXCED_RANGE\` error on failure instead of calling the
shell or falling back to permanent deletion. Tests cover exact capacity,
the next byte over capacity, MAX_PATH boundaries, null/empty inputs, and
unchanged destination memory after failure.

The helper is deliberately restricted to the **legacy ANSI shell path**.
It does not attempt to turn an ACP name into a lossless Unicode identity.

## Changes intentionally not copied

The historical \`win32widepaths.h\` and extensive \`worker.cpp\` rewrite
would convert pre-existing \`char*\` names through CP_ACP. That conversion
cannot recover names already substituted or aliased during enumeration and
would introduce a second filesystem adapter alongside the modern W-based
implementation on \`main\`. Importing those changes would greatly increase
the regression and data-integrity risk without proving end-to-end support.

The older \`tests/Win32FilesystemIntegrationTests.cpp\` overlaps substantially
with current Windows/.NET, native Unicode path and 32700-unit GUI tests.
Its trailing-dot/space deletion scenario is still a worthwhile independent
follow-up acceptance case for the real Win32 W operation path; it is **not**
evidence that the legacy ANSI worker should be made to delete such names.

## Branch-retention policy

Branches fully contained in \`main\` can be safely deleted after verifying
their remote refs and retaining PR links. Diverged branches should be retained
for historical reference until each has been explicitly audited; do not
force-merge or delete them simply to reduce the branch count. No release
or broad Unicode/long-path feature claim follows from this reconciliation.

## Verification required

- Compile and run \`tools/tests/shell_file_operation_name_list.cpp\`
  (registered in \`manage.cmd --test\` and in the long-path CI workflow).
- Build both Win32 Debug and x64 Debug with warning-as-error CI.
- Run the real Windows \`--test-all\` GUI regression before merging this
  follow-up PR, especially the F8 short-path Recycle Bin scenarios.
- Recycle Bin **restoration** and legacy plug-in integration remain separate
  acceptance gaps.

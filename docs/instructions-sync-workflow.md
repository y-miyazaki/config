# Instructions Sync Workflow

## Overview

This document explains how instruction files are synchronized with review skill references, what was changed in this session, and how to safely use the sync script in future updates.

## Scope

Applies to instruction files under `.apm/instructions/*.instructions.md` and review references under `.apm/skills/*-review/references/`.

## What Was Standardized

The following standards were aligned across instruction files:

1. Keep a consistent 5-chapter H2 structure:
   - `## Scope`
   - `## Standards`
   - `## Guidelines`
   - `## Testing and Validation`
   - `## Security Guidelines`
2. Keep `Check:` lines in `Guidelines` (do not split them into a separate chapter).
3. Keep `### Code Modification Guidelines` in every instructions file.
4. Remove numeric prefixes from Guidelines H3 headings (for example, `### 6. Best Practices` -> `### Best Practices`).
5. Do not emit empty H3 sections in generated Guidelines.
6. Avoid duplicate TEST/SEC review criteria outside `Guidelines` in `instructions.instructions.md`.

## Source of Truth and Sync Direction

The sync direction is:

1. `category-*.md` -> normalize ID/LEVEL format.
2. `common-checklist.md` -> regenerate from category headers and ID lines.
3. `*.instructions.md` -> regenerate `## Guidelines` from parsed category sections and checks.

`Guidelines` is the review-criteria hub. `Testing and Validation` and `Security Guidelines` remain as operational chapters.

## Script

Path:

- `scripts/apm/sync_guidelines_from_categories.pl`

Main behavior:

1. Normalizes category rule titles to `**ID (LEVEL): Title**`.
2. Regenerates checklist entries from category sections.
3. Regenerates Guidelines with:
   - H3 section headers (normalized, non-numeric)
   - Rule bullets (`- ID (LEVEL): ...`)
   - `Check:` child bullets
4. Appends `### Code Modification Guidelines` using skill-specific defaults.
5. Skips empty sections during generation.

## How To Run

```bash
cd /workspace
scripts/apm/sync_guidelines_from_categories.pl
```

## Required Re-Evaluation After Instruction Changes

Whenever any `*.instructions.md` file is changed, run a re-evaluation pass.

Recommended checks:

```bash
# 1) Ensure chapter order and 5 H2 chapters
for f in .apm/instructions/*.instructions.md; do
  awk 'BEGIN{s=0;st=0;g=0;t=0;sec=0} /^## Scope$/{s=NR} /^## Standards$/{st=NR} /^## Guidelines$/{g=NR} /^## Testing and Validation$/{t=NR} /^## Security Guidelines$/{sec=NR} END{print FILENAME, (s<st && st<g && g<t && t<sec)?"OK":"NG"}' "$f"
done

# 2) Ensure no numbered Guidelines H3
grep -nE '^### [0-9]+\.' .apm/instructions/*.instructions.md || true

# 3) Ensure Code Modification Guidelines exists in each file
for f in .apm/instructions/*.instructions.md; do
  grep -q '^### Code Modification Guidelines' "$f" || echo "Missing: $f"
done
```

## Decisions Captured

1. Keep `Check` content in `Guidelines`.
2. Keep operational content in `Testing and Validation` and `Security Guidelines`.
3. In `instructions.instructions.md`, avoid duplicating TEST/SEC review criteria outside `Guidelines`.

## Troubleshooting

If structure looks broken after sync:

1. Verify category files contain valid section headers (`## ...`) and rule titles (`**ID (LEVEL): Title**`).
2. Re-run the sync script.
3. Re-run the re-evaluation commands above.
4. If needed, inspect generated Guidelines boundaries between `## Guidelines` and `## Testing and Validation`.

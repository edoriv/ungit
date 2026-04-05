# Contributing to UNGIT

Thanks for contributing.

## Ground rules

- Keep UX native, clear, and low-friction.
- Prefer explicit filesystem-backed behavior over hidden magic.
- Do not introduce destructive restore logic.
- Keep terminology aligned with UNGIT concepts (Project, Snapshot, Timeline, Restore).

## Development setup

```bash
swift test
xcodebuild -project "UNGIT.xcodeproj" -scheme "UNGIT" -configuration Debug build
```

## Pull request checklist

- [ ] Build succeeds.
- [ ] Tests pass.
- [ ] User-facing behavior is documented (README/help/notes if needed).
- [ ] Restore/snapshot safety behavior remains intact.

## Scope guidance

Prefer small, reviewable changes. For larger refactors, include rationale and migration notes.

# UNGIT

UNGIT is a macOS SwiftUI app for local-first snapshot versioning without Git abstraction.

It creates real zip archives and JSON manifests directly in each project's `.ungit` folder so solo developers can checkpoint, review, and restore work with clear timeline context.

## Why UNGIT Exists

I did not build UNGIT to replace Git.
I built it because Git never fit the way I actually work.

I am not a team coordinating branches and merges across multiple developers.
I am building, exploring, breaking things, fixing them, and trying to move forward without losing myself along the way.

Git felt powerful, but it felt like the wrong size shoe.
What I needed was not traditional version control.
What I needed was continuity.

## The Problem It Solves

When you are coding with AI, things change faster than you can reliably track:

- Multiple files change at once.
- You do not always remember why something worked.
- Fixes can introduce silent regressions.
- AI sometimes gets bold and "fixes" things you did not ask it to fix.
- You can lose the thread of the project itself, not just the code.

That drift is the real problem.
It is not only about losing a file diff.
It is about losing intent, decisions, confidence, and your ability to recover cleanly.

## What UNGIT Actually Is

UNGIT is not a branching system.
It is a timeline of truth.

Instead of centering the workflow around commits and branches, UNGIT centers it around:

- Snapshots: what the project looked like
- Landmarks: important moments like milestones, release candidates, and releases
- Fork points: places where direction changed
- Proof: whether something actually worked, not just compiled
- Risk and outcome: what you expected versus what actually happened

It tries to build a trustworthy narrative of a project, not just a history of file changes.

## Why It Feels Different

UNGIT is not only about saving code.
It is meant to actively protect the work.

- It reminds you to snapshot when risky changes pile up.
- It gates dangerous actions like restore behind explicit approval.
- It verifies integrity against known-good states.
- It helps detect drift across the timeline.
- It keeps the filesystem as the source of truth.

It does not trust memory, human or AI.
It trusts evidence on disk.

## Why AI Needed This

AI is powerful, but it is also unpredictable.

It can forget context, overreach, or try to fix everything at once.
UNGIT exists as a counterweight to that.

It gives AI:

- a grounded timeline
- explicit restore points
- verified states
- structured project memory

And it gives the human operator:

- control
- visibility
- confidence

## Why It Works For Me

UNGIT matches how I actually think while building software:

- I remember moments, not commits.
- I think in before and after, not only in diffs.
- I need to know what changed and why, not just that it changed.
- I need to recover quickly when something breaks.
- I need to trust that I cannot accidentally lose everything.

UNGIT lets me move fast without feeling like I am gambling with the project.

## Why Share It

This was not built for a market.
It was built because I needed it.

But I am probably not the only one who works this way.
UNGIT may be useful to:

- solo builders
- AI-assisted developers
- people who do not live inside Git workflows
- people who have lost hours or days to bad changes

It is open source, provided as-is, and shared because it solved a real problem for me.

I may keep improving it when I need to, but I am not treating it as a request-driven product or promising ongoing feature work.

## In One Line

UNGIT is a way to stay oriented in your own project when speed, complexity, and AI start to pull you off course.

## Status

This project is free, open source, and provided as-is.

## Core concepts

- Project
- Snapshot
- Path
- Timeline
- Restore
- Milestone
- Notes

## What UNGIT does

- Saves snapshots as:
  - `.ungit/manifests/<SNAPSHOT_ID>.json`
  - `.ungit/snapshots/<SNAPSHOT_ID>.zip`
- Keeps timeline history filesystem-backed.
- Supports proof states: `Verified`, `Unverified`, `Broken`.
- Supports proof modes: `Lightweight Proof`, `Archive Proof`.
- Uses restore safety controls:
  - automatic safety snapshot
  - staged restore flow
  - explicit restore approval token
  - Xcode-aware restore protection

## Build

Requirements:

- macOS
- Xcode 16+
- Swift 5.10+

Build app (Release):

```bash
xcodebuild -project "UNGIT.xcodeproj" -scheme "UNGIT" -configuration Release -derivedDataPath .build-xcode build
```

Build MCP server (Release):

```bash
swift build -c release --product ungit-mcp
```

## MCP setup (Codex)

Use the bundled MCP binary from the app:

- Command to launch:
  - `/Applications/UNGIT.app/Contents/MacOS/ungit-mcp`
- Working directory:
  - `/` (recommended)
  - `~/` (alternative)

## Typical workflow

1. Open project in UNGIT (initializes `.ungit`).
2. Capture quick checkpoints during work.
3. Use Pre-Change before structural edits.
4. Use Milestone / Release Candidate / Release landmarks.
5. Verify key snapshots before relying on rollback.

## Command examples

- `UNGIT quick save`
- `UNGIT quick pre-change`
- `UNGIT quick milestone`
- `UNGIT verify snapshot <snapshot-id> archive`
- `UNGIT handoff`
- `UNGIT restore snapshot <snapshot-id>`

## Data and privacy

UNGIT is local-first.

- Your project snapshots and metadata stay in your project folder.
- No cloud sync is required for core functionality.

## Limitations

- macOS-focused.
- Operator-assisted safety model (not unattended automation).
- You should still keep independent backups for mission-critical work.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

See [SECURITY.md](SECURITY.md).

## Support

See [SUPPORT.md](SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).

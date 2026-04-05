# UNGIT

UNGIT is a macOS SwiftUI app for local-first snapshot versioning without Git abstraction.

It creates real zip archives and JSON manifests directly in each project's `.ungit` folder so solo developers can checkpoint, review, and restore work with clear timeline context.

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

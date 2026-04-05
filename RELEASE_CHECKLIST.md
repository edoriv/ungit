# UNGIT Release Checklist

Use this checklist before calling a version "known good" for broader project usage.

## 1) Build and Tests
- Run `xcodebuild -project UNGIT.xcodeproj -scheme UNGIT -configuration Debug build`
- Run `swift test`
- Confirm no failing tests in:
  - command parser + app-path command execution
  - restore drills (mixed project shape)
  - manifest corruption resilience
  - restore preflight checks

## 2) Restore Safety Validation
- Run `UNGIT preflight restore`
- Confirm preflight reports archive validation success
- Perform one real restore drill in a disposable project folder
- Confirm safety snapshot is created and rollback path is available

## 3) Proof and Rollback Readiness
- Verify at least one Trusted Rollback snapshot using Archive Proof
- Confirm proof state and proof mode are visible in timeline + inspector
- Confirm latest trusted rollback has proof state `Verified`

## 4) Command Contract Audit
- Confirm managed command list in `AGENTS.md` matches parser behavior
- Confirm cheat sheet command list matches parser behavior
- Confirm command-default behavior (quick save type/title alignment) still passes

## 5) Mark Known-Good Version
- Create an annotated git tag using format:
  - `ungit-known-good-YYYYMMDD-HHMM`
- Include release note summary in the tag annotation:
  - scope covered
  - restore drill result
  - proof verification result
  - any known limits

## Current Confidence
- Suitable: personal/internal projects with operator oversight
- Requires checklist completion before broader mission-critical usage

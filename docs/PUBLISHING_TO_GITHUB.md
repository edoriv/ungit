# Publish UNGIT to GitHub

## 1. Initialize git (if needed)

```bash
cd "/Users/efo/xcode projects/2026/UNGIT"
git init
git branch -M main
```

## 2. Add files and commit

```bash
git add .
git commit -m "Initial open-source release (as-is)"
```

## 3. Create repo on GitHub

Create a new repo (no README/license generated on GitHub).

Example:

- owner: your account
- repo: `UNGIT`
- visibility: Public

## 4. Connect remote and push

```bash
git remote add origin git@github.com:<YOUR_USER>/UNGIT.git
git push -u origin main
```

If using HTTPS:

```bash
git remote add origin https://github.com/<YOUR_USER>/UNGIT.git
git push -u origin main
```

## 5. Create first release tag

```bash
git tag -a v0.1.0 -m "UNGIT v0.1.0"
git push origin v0.1.0
```

Then create a GitHub Release for `v0.1.0` and paste highlights from `CHANGELOG.md`.

## 6. Optional: attach built app artifact

You can zip and attach `/Applications/UNGIT.app` (or built Release app) to the release.

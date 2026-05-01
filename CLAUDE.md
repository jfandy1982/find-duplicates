# CLAUDE.md

## Repository Purpose

Docker image wrapping the `fdupes` CLI tool to find duplicate files on a filesystem (NAS/server). Published to Docker Hub as `jfandy1982/find-duplicates`.

## Known Structure

- `experiments/` — contains experimental attempts as well as test data for checking the functionality locally
- `node_modules/` — exists locally but is gitignored; not committed to the repo

## Tooling

- GitHub Actions SHAs are manually verified and pinned — do not flag pinned SHAs as outdated without checking first
- Renovate: `renovate.json` in `.github/` is the repository-specific Renovate entry point; the `schedule` override there is intentional
- pre-commit hook runs `lint-staged` (Prettier + cspell) on `*.json`, `*.md`, `*.yml`

### Commands

These NPM scripts can be used beside pre-commit-hooks to enforce proper spelling and formatting.

```bash
npm run format:all          # format all JSON/MD/YML files with Prettier
npm run format:all:check    # verify formatting without writing
npm run spell:check:all     # run cspell on the whole repo
```

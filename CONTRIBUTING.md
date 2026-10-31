# Contributing

## Workflow

In short: every change starts from a GitHub issue, lives on a branch from `main` named
`<type>/<issue>-<slug>` (e.g. `feat/12-site-list`), is committed in small
[Conventional Commits](https://www.conventionalcommits.org/), and lands through a PR
that says `Closes #N`. CI must be green; PRs are squash-merged after review, so the PR
title becomes the commit on `main`. A small fix that blocks the current ticket can ride
on the same branch as its own `fix:` commit, noted in the PR and under `Fixed` in
`CHANGELOG.md`; anything bigger gets its own issue and PR.

## Commit scopes

Scopes used in this repo: `core`, `helper`, `app`, `scripts`.

## Versioning and releases

[Semantic Versioning](https://semver.org/). While the project is `0.x`, a minor bump
(`0.1 → 0.2`) may include breaking changes.

To cut a release:

1. Move the `[Unreleased]` entries in `CHANGELOG.md` under a new version heading.
2. Update `VERSION` and `version` in `Sources/FocusGuardHelper/main.swift`.
3. Merge to `main`, then tag and publish:
   ```bash
   git tag -a v0.1.0 -m "v0.1.0"
   git push origin v0.1.0
   ./scripts/build-app.sh && ditto -c -k --keepParent build/FocusGuard.app FocusGuard-0.1.0.zip
   gh release create v0.1.0 FocusGuard-0.1.0.zip --notes-file <(sed -n '/## \[0.1.0\]/,/## \[/p' CHANGELOG.md)
   ```

## Code guidelines

- Logic that decides *what* to do goes in `FocusGuardCore`, with tests. The app and the
  helper should stay thin.
- Anything that touches the helper or `/etc/hosts` needs extra scrutiny: validate input,
  never widen the sudoers rule, keep writes atomic.
- Run `./scripts/test.sh` before pushing.

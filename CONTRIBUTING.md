# Contributing

## Workflow

`main` is always releasable. All work happens on short-lived branches and lands through a
pull request.

1. Pick or open an issue, so the change has a reason and a place for discussion.
2. Branch from `main` with a type prefix:
   - `feat/…`: new functionality
   - `fix/…`: bug fixes
   - `docs/…`, `test/…`, `refactor/…`, `build/…`, `ci/…`
3. Commit in small, focused steps (see below).
4. Open a PR using the template and link the issue (`Closes #N`).
5. CI must be green. PRs are **squash-merged**, so the PR title becomes the commit on
   `main` and has to follow the commit convention too.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<optional scope>): <imperative summary, ≤ 72 chars>

<why the change was made, wrapped at 72 columns>
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore`.
Scopes used in this repo: `core`, `helper`, `app`.

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

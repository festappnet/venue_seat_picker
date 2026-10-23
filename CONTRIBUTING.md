# Contributing

Issues and pull requests are welcome. Please keep the package independent of
any backend, state-management library, or Festapp domain model.

Before opening a pull request, run:

```bash
flutter pub get
flutter analyze
flutter test
dart pub publish --dry-run
```

Public API changes must include tests, documentation, and a changelog entry.
By contributing, you agree that your contribution is licensed under the MIT
License used by this repository.


For local work before the core is published, run
`python3 tool/configure_workspace.py` then `fvm flutter pub get`.
The generated overrides resolve `venue_layout_core` from `packages/` and are
excluded from archives. The shipped manifest retains its concrete semver range.
The tested toolchain is pinned in `.fvmrc` (Flutter 3.47.2 / Dart 3.13.2).
Use `fvm` for all SDK commands. Run `tool/demo.sh build`, `tool/demo.sh check`
and `tool/archive_check.sh` for the standalone distribution gates. The last
command creates public archives without uploading them and tests unpacked
consumers. A dirty-checkout warning is expected while changes remain uncommitted.
Font outline regeneration requires Python fonttools 4.67.0; already-built
fixtures and demo kits have no Python/font parsing runtime dependency.

Use pnpm 11.24.0 for the web package: run `pnpm install --frozen-lockfile`
in `web/` before the distribution gates.

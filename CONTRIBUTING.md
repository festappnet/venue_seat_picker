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
The tested toolchain is pinned in `.fvmrc` (Flutter 3.47.7 / Dart 3.13.5).
The public wrapper minimum is Flutter 3.44 / Dart 3.12; the core minimum is Dart 3.10.
See [compatibility checks](doc/compatibility.md) before changing SDK or dependency bounds.
Use `fvm` for all SDK commands. Run `tool/demo.sh build`, `tool/demo.sh check`
and `tool/archive_check.sh` for the standalone distribution gates. The last
command creates public archives without uploading them and tests unpacked
consumers. A dirty-checkout warning is expected while changes remain uncommitted.
Font outline regeneration requires Python fonttools 4.67.0; already-built
fixtures and demo kits have no Python/font parsing runtime dependency.

Use pnpm 11.24.0 for the web package: run `pnpm install --frozen-lockfile`
in `web/` before the distribution gates.

## Dependency and SDK compatibility policy

Do not automatically track the newest dependency or raise the package's minimum
SDK when upgrading the development toolchain. Keep the oldest tested SDK and
compatible dependency versions that support the required behavior.

- A higher minimum needs a concrete API, language feature, correctness or
  security requirement. Prefer an API available across the supported range
  when it preserves behavior; describe any necessary compatibility loss in the
  changelog.
- Use compatible ranges and the existing lowest/latest resolution CI coverage.
  Keep exact pins only for documented constraints such as converter provenance.
- Test the declared minimum and current SDKs before publishing. A successful
  build on the newest SDK does not prove the minimum. Keep test-only tool
  requirements out of the consumer runtime contract.
- Remove unused direct declarations, while retaining dependencies that implement
  public functionality. Do not introduce forks or shipped overrides to hide a
  dependency conflict.

Npm release automation and its one-time account setup are documented in
[Automatic npm publishing](doc/npm-publishing.md).

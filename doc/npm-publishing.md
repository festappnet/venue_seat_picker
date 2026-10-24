# Automatic npm publishing

The CI workflow builds and tests the package, runs the archive gate and retains
its exact npm tarball. The publishing job consumes that artifact from the same
run and verifies its source commit and package version. It publishes missing
versions from main using pnpm 11.24.0 and GitHub OIDC; already published versions
are skipped. A failed registry lookup stops the job. Pull requests never publish.

This does not require a local npm login or a long-lived npm write token.
GitHub repository access alone cannot configure trust in an npm owner's account.

## One-time npm account setup

The public registry currently has no public `@festapp/venue-layout` package.
An npm owner of the `@festapp` scope must create its first public publication and
then add the following trusted publisher in the package's npm settings:

- Provider: GitHub Actions
- Organization: `festappnet`
- Repository: `venue_seat_picker`
- Workflow filename: `ci.yml`
- Environment: leave empty
- Allowed action: enable direct `npm publish`

Follow the [npm trusted publishing setup](https://docs.npmjs.com/trusted-publishers/).
After npm trust is configured, activate the prepared job:

```sh
gh variable set NPM_TRUSTED_PUBLISHING --body true --repo festappnet/venue_seat_picker
gh workflow run ci.yml --ref main --repo festappnet/venue_seat_picker
```

Future verified main builds publish automatically when `web/package.json` selects
an npm version that is not yet published. Bump that version for a new npm release.
The activation variable stays unset until npm account setup is complete; a
skipped publishing job does not claim a registry release. Dart pub.dev releases
and Festapp's direct source-archive integration remain independent.

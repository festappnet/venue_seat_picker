# Publishing Venue Layout to npm

Venue Layout is the product name. Its JavaScript package is
`@festapp/venue-layout`; the Flutter package remains `venue_seat_picker`.
The `@festapp` scope is already used by `@festapp/banksync`.

## Release flow

The repository follows the BankSync publishing model: promotion from main,
immutable release tags, a protected `npm` environment and GitHub OIDC.
No local npm login or stored write token is needed for normal releases.

1. Increase the JavaScript version in `web/package.json` and merge the change.
2. Wait for CI on that exact main commit to pass.
3. Run the **Promote npm release** workflow with that JavaScript version.
4. Promotion creates the protected `npm-vVERSION` tag and dispatches `release.yml`.
5. The release qualifies the exact source using the existing CI/archive gate.
   Its publishing job uses the `npm` environment review, then uploads the exact
   tested tarball through npm trusted publishing with provenance. The identical
   archive and its SHA-256 are attached to the GitHub release.

For the prepared JavaScript version:

```sh
gh workflow run promote.yml --ref main -f version=0.3.5 --repo festappnet/venue_seat_picker
```

The wrapper's pub.dev version is independent of the JavaScript version; npm tags
therefore use `npm-v` instead of sharing an ambiguous `v` tag. Failed registry
lookups stop publication. A retry skips an existing version only when its npm
integrity matches the exact qualified tarball. Different bytes require a new version.

## One-time npm package setup

BankSync's trusted publisher does not automatically authorize another package.
An npm owner of `@festapp` must bootstrap the first public
`@festapp/venue-layout` publication, then configure its trusted publisher:

- Provider: GitHub Actions
- Organization: `festappnet`
- Repository: `venue_seat_picker`
- Workflow filename: `release.yml`
- Environment: `npm`
- Allowed action: enable direct `npm publish`

See [npm trusted publishing](https://docs.npmjs.com/trusted-publishers/) and
[npm trust](https://docs.npmjs.com/cli/v11/commands/npm-trust/). GitHub repository
access alone cannot configure npm account trust. Scope ownership and a valid
publisher configuration are separate requirements.

The GitHub side uses immutable `npm-v*` tags and the same npm environment reviewer
as BankSync. This repository has no alternate publishing job in CI and no
activation flag. Pub.dev releases and Festapp's verified source-archive integration
remain independent of npm publication.

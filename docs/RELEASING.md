# Maintainer release checklist

The local repository is MIT licensed. Building it does not publish a GitHub
repository, release, PyPI/npm package, or Homebrew tap. There is no Python runtime.

1. Run `swift test` with a supported Xcode toolchain. Tests include a real Swift
   MCP client launching the executable, credential isolation, corruption handling,
   and atomic report imports. Public network checks are separate, not required in CI.
2. Run `./scripts/package-macos.sh`. This produces a universal Intel/Apple Silicon
   executable, source/license information, an installer, and SHA-256 checksum under
   `dist/`. The archive is a development release with an ad-hoc signature by default.
3. For a public binary, supply `APPSCOPE_SIGNING_IDENTITY` referencing a Developer
   ID Application certificate in the local Keychain and `APPSCOPE_NOTARY_PROFILE`
   referencing an existing `notarytool` credential profile. Rerun the package script.
   It signs with hardened runtime, submits a ZIP with the same executable for
   notarization, and waits for Apple's result. The bare CLI cannot be stapled;
   Gatekeeper checks the notarization ticket online. Do not mark an ad-hoc build
   as notarized. Verify the public download on a clean Mac before announcing it.
4. Create the chosen public repository and publish the reviewed source. Tag the
   verified version, then upload the matching archive and checksum to that tag's
   GitHub Release. Neither public publishing nor credential creation is automatic.
5. Create a Homebrew tap repository with a `Formula/` directory. Generate a formula
   only after the release URL exists:

   ```sh
   ./scripts/homebrew-formula.sh \
     https://github.com/OWNER/AppScope/releases/download/v0.1.0/appscope-0.1.0-macos-universal.tar.gz \
     dist/appscope-0.1.0-macos-universal.tar.gz > Formula/appscope.rb
   ```

   `OWNER` is a placeholder for the actual repository owner. Review the formula,
   test its install, then publish it in `OWNER/homebrew-tap`. Users can then run
   `brew install OWNER/tap/appscope`. No such tap is claimed to exist before publishing.
6. Each upgrade updates the version, archive URL and checksum together. Test both
   first install and replacement while preserving user configuration/history.

CI only uploads build artifacts; it does not publish code or a Homebrew formula.
The signing identity/profile values are references, not private key contents.
Apple Ads/App Store Connect credentials are entirely unrelated to signing and
must never be supplied to a build or CI job.

## Current qualification limits

Tests with synthetic Apple responses establish local behavior, not your account's
access. Before describing Apple account integration as qualified, record a live
`keyword_suggestions` call, a report sync for a real app, and a comparison of report
totals/coverage against App Store Connect. Validate keyword search ordering against
physical-device storefront checks before offering a device-rank accuracy claim.

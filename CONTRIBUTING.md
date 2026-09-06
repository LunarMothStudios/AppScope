# Contributing to AppScope

AppScope is a small local data tool for agents. Contributions should make its
evidence more useful and trustworthy while keeping installation and operation
simple. Start with the [architecture](docs/ARCHITECTURE.md),
[data contract](docs/DATA-CONTRACT.md) and [security model](SECURITY.md).

## Build and test

Use macOS 14+, Swift 6+ and a matching macOS SDK. From the checkout root:

```sh
swift build
swift test
swift run appscope-docs --check
swift run appscope --help
```

With full Xcode installed but Command Line Tools selected, set the developer
directory for this Terminal session first:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

Keep dependencies pinned in `Package.resolved`. The tests use Swift Testing and
synthetic provider responses, including a real MCP client launching the debug
executable over stdio. They do not require Apple credentials or live provider
requests. The test suite currently contains 21 tests; the dated
[validation record](docs/VALIDATION.md) explains what passing establishes.

To test the MCP subprocess against a packaged executable, set
`APPSCOPE_TEST_BINARY` to that binary's absolute path when running the integration
test. Packaging and its separate runtime qualification are described in
[releasing](docs/RELEASING.md).

## Safe development data

Use a private scratch directory for manual runs. Set `APPSCOPE_DATA_DIR` to it,
ensure no unrelated `APPSCOPE_CONFIG` override is inherited, then run `setup`.
Do not use a real account database as a test fixture. Keep network smoke tests
opt-in, separate from deterministic tests, and bounded to a few calls.

Never commit private keys, account config, local databases, authenticated provider
exports, personal briefs or signed download URLs. `.gitignore` covers common
locations and extensions; it is not a secret scanner. Before committing, inspect
`git diff --cached`. Make synthetic fixtures that demonstrate the behavior
without retaining identifiable account data.

## Behavioral changes

Keep results explicit about source, country, collection time, search depth,
coverage and unavailable fields. Do not fill unknown popularity with invented
volumes, relabel API order as device rank, sum non-additive unique counts or imply
audience demographics from metadata. Do not add automatic listing changes or
campaign spend to an analysis workflow.

For data handling changes, add a focused regression demonstrating the defect and
the expected ordinary/error behavior. Important boundaries include incomplete
report imports, cross-host pagination, missing metrics, corrections, duplicate
search results, caching and SQLite transactions. Verify failures preserve valid
earlier data and return useful sanitized errors. Avoid tests that just repeat
implementation details.

## Keep the handbook accurate

Every tool needs an example in `examples/tool-calls.json`. Those examples use a
fictional app ID and are checked against the runtime catalog. When a tool changes:

1. Update its schema/description and service implementation together.
2. Update its synthetic example, response guide and relevant workflow.
3. Run `swift run appscope-docs` to regenerate `docs/TOOLS.md` and
   `examples/tool-catalog.json` from `ToolCatalog.all`.
4. Review the generated diff, then run `swift run appscope-docs --check`.

The check validates example coverage/types, selected semantic fields, generated
file freshness, fenced JSON examples, and relative file links. It does not call
Apple, verify account permissions, validate external URLs or check Markdown
anchors. Human review still matters for explanations and response semantics.
CI and packaging run it so public docs cannot silently drift from tool schemas.

Keep beginner instructions task-oriented. Use placeholders only when explicitly
labeled, and do not invent repository URLs, credentials, tap names or validation
claims. The compiled archive includes the docs, so internal documentation links
must work without a source checkout. In architecture prose, render source paths
as code instead of linking to files absent from the archive.

## Before opening a pull request

Run the appropriate tests, documentation check and `git diff --check`. With a
toolchain that includes Swift Format, use `swift format lint --strict` on changed
Swift files. Run `bash -n` on changed shell scripts. No broad test expansion is
needed for a prose-only edit.

Describe the concrete problem and resulting behavior, the relevant validation,
and any remaining live-account or platform checks. Update the changelog for
user-visible changes. Keep commits focused. Passing fixtures or building both
CPU slices does not establish live Apple access, Intel runtime behavior or
notarization.

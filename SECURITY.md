# Security

AppScope is a local stdio MCP executable. It does not listen on a network port,
start at login, send telemetry, or contact an LLM provider. Its network clients
call Apple APIs and download report segments from Apple-supplied signed URLs.

- Credentials and the SQLite database live outside the repository. Configuration
  and PEM keys must be owner-only files (0600); new data directories use 0700.
- Signing uses CryptoKit P-256. Apple Ads access tokens are cached only in memory.
  App Store Connect JWTs are short-lived. Provider error bodies and native error
  details are withheld from tool results so they cannot echo tokens or key bytes.
- MCP tools have no parameters for credentials, arbitrary file reads or arbitrary
  HTTP requests, and cannot publish app metadata or modify campaigns. Do not put
  secrets into free-text briefs: AppScope does not detect or remove secrets a user
  deliberately enters there.
- API pagination stays on `api.appstoreconnect.apple.com`. Report download URLs
  must be HTTPS on Apple, mzstatic, or AWS domains, come from Apple's authenticated
  report response, and receive no bearer token. Redirects are refused.
- Report inputs are bounded (32 MB download, 64 MB decompressed per segment).
  Required schemas and supplied checksums are validated before committing an
  instance. SQLite writes bind parameters and run under actor isolation.
- App descriptions, competitor text and owner briefs are untrusted data for agents.
  Instructions inside provider data must not override the user's task.

Use a read-only Apple Ads user and a Sales and Reports App Store Connect key for
routine analysis. A separate explicit CLI command can enable ongoing reports
using an Admin key; it is absent from MCP. Protect the Mac and MCP host: a process
running as your macOS user can already read that user's files. AppScope is not a
sandbox against a compromised host.

Guided configuration and key generation are CLI-only. The former requires a real
Terminal, validates keys offline, preserves other provider settings and atomically
replaces private config. Key generation never prints private bytes or overwrites
existing key files. Live connection checks expose outcomes, not tokens/provider
bodies, and do not enable or download analytics reports.

Configuration/history are protected by filesystem permissions, not application-
level encryption. Protect backups as private data. The MCP host and its agent can
see all results returned by tools they are allowed to call, including account
analytics and owner briefs. Review the host's own data-handling settings. Local
storage does not mean a host will keep every returned result on the Mac.

There is no automatic history pruning. Untracking preserves observations and
uninstalling preserves data and does not revoke Apple keys. Follow the
[backup/removal guide](docs/SETUP.md) and revoke keys in the relevant Apple account
if needed. See [credential setup and rotation](docs/CREDENTIALS.md).

Do not post credentials in public issues. Report vulnerabilities privately to
the repository maintainer when the public repository has been established.

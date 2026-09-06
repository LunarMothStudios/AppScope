# Setup

AppScope works with any MCP host that can launch a local stdio process. There is no
HTTP listener, cloud account, bundled LLM, scheduled daemon, or required GUI.

## Install from Git

Clone the AppScope repository, enter the checkout, then run:

```sh
./scripts/install.sh
"$HOME/.local/bin/appscope" setup
"$HOME/.local/bin/appscope" doctor
```

The source install requires Swift 6+ and a macOS SDK. With full Xcode installed,
our scripts select it automatically. Otherwise use matching Command Line Tools.
The resulting executable does not require a Swift compiler or Python on the
user's Mac. macOS 14+ is required.

`APPSCOPE_PREFIX=/your/prefix ./scripts/install.sh` changes the install location.
The default is `~/.local/bin/appscope`; add that folder to PATH if desired.

To update, review/pull a new version in the checkout and rerun the installer.
Remove the installed executable to uninstall; configuration/history stay intact.
Delete the AppScope data directory only if you also want to remove all history.

## Install a compiled release

Extract the macOS universal archive and run its `install.sh`. It installs only
`appscope`, supporting both Apple Silicon and Intel. Run `appscope setup` using
the installed absolute path. Use signed/notarized public releases when available.
An ad-hoc development build is not a notarized public release. Do not disable
Gatekeeper as an installation step.

A public GitHub release and Homebrew tap are not created by a local build. The
maintainer's publishing steps are in [RELEASING.md](RELEASING.md).

## Connect the agent

`appscope setup` prints the complete MCP configuration with the actual executable
path. Copy it into your host's MCP configuration. The shape is:

```json
{
  "mcpServers": {
    "appscope": {
      "command": "/absolute/path/to/appscope",
      "args": ["serve"]
    }
  }
}
```

For hosts with a different configuration format, use the same command and args.
Set a tool timeout of at least 120 seconds for ranking batches, and longer for
initial Apple analytics imports. Enable only the tools you want the agent to use.
MCP results distinguish local writes (tracking/history) from read-only calls.
No MCP tool can modify Apple metadata, create campaigns, or spend money.

## Public data first

No credentials are needed for `search_apps`, `app_profile`, `analyze_keyword`, or
keyword tracking/history. Discover your numeric app ID from `search_apps`; check
the returned title, developer and URL before tracking it. Save an app brief and
choose a country (default `us`). Rankings start from selected/discovered terms,
not an exhaustive list of every term an app ranks for.

## Apple credentials

Setup creates an empty, owner-readable `config.json` in
`~/Library/Application Support/AppScope`. Edit that local file, never a source
file or MCP prompt. Keys must be P-256 PEM files with mode 0600 and live outside
the Git checkout. Configuration stores paths to the private keys, not their bytes.
Tokens and JWTs remain in memory and are not logged or saved in the database.

```sh
chmod 600 /absolute/path/to/private-key.p8
```

Override the data directory with `APPSCOPE_DATA_DIR` and the configuration file
with `APPSCOPE_CONFIG`. Set the same environment in the MCP host if using overrides.

### Apple Ads

An Apple Ads account administrator must grant API access. Prefer an **API Account
Read Only** user. Generate a P-256 key locally, give Apple the public key, and keep
the private key local. Account Settings → API supplies client ID, team ID and key
ID. Add the **Platform API ad account ID**; it is not assumed to be the legacy org ID.

Fill in the local `apple_ads` object: `client_id`, `team_id`, `key_id`,
`ad_account_id`, and `private_key_path`. Then call `keyword_suggestions` for an app
to validate access. No campaign or ad spend is created by AppScope.

See [Apple's API setup documentation](https://ads.apple.com/maps/apple-ads/help/campaigns/0022-use-apple-ads-platform-api).

### App Store Connect

Create a team API key and fill in the local `app_store_connect` object:
`issuer_id`, `key_id`, and `private_key_path`. Keep this separate from the Apple
Ads key. Use a **Sales and Reports** key for routine analytics downloads.

An **Admin** key is required once to create ongoing report requests. With an
Admin key configured locally, run:

```sh
appscope enable-reports NUMERIC_APP_ID --confirm
```

Then switch to the Sales and Reports key for ordinary use. The enablement command
is idempotent for an existing active ongoing request and is not exposed through
MCP. Apple's first reports may take 24–48 hours. Call `app_performance` to sync.
Stopped requests need to be re-enabled. Data is cached so repeated reads work
offline; reports show the last import status and data coverage.

See [Apple's role and report guidance](https://developer.apple.com/documentation/appstoreconnectapi/downloading-analytics-reports).

`doctor` reports configuration presence, not successful account authentication.
Successful live tool calls are the account access check. Report schema/auth flows
have automated fixture coverage; your account still needs live qualification.

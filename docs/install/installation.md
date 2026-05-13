# Installation

NopeID is installed with the public bootstrap script:

```sh
curl -fsSL https://nopeid.com/install.sh | sh
```

Production installs use fixed managed paths:

```text
/opt/nopeid/current
/opt/nopeid/versions/<version>
/opt/nopeid/bin/nopeid
/opt/nopeid/bin/nopeid-agent
/opt/nopeid/bin/nopeid-helper
/Library/LaunchDaemons/com.nopeid.agent.plist
/var/lib/nopeid
/var/log/nopeid
/var/run/nopeid-install.lock
```

The installer downloads and verifies release artifacts as the invoking user, then
uses `sudo` only for the privileged system install phase. Production installs do
not accept custom install roots.

Supported options:

```sh
curl -fsSL https://nopeid.com/install.sh | sh -s -- --yes
curl -fsSL https://nopeid.com/install.sh | env NOPEID_VERSION=v0.1.2 sh
curl -fsSL https://nopeid.com/install.sh | sh -s -- --dry-run
```

NopeID requires macOS 26 Tahoe or newer.

## Dev Installs

Development mode is explicit:

```sh
./install.sh --dev --binary /path/to/nopeid --helper /path/to/nopeid-helper
```

Dev mode may point launchd at local build outputs. It stops any production
NopeID service first because two NopeID agents must not run at the same time.
Dev mode does not promise production rollback, receipt, or versioned layout
behavior.

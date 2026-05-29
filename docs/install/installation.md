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
/usr/local/bin/nopeid
/Library/LaunchDaemons/com.nopeid.agent.plist
/var/lib/nopeid
/var/log/nopeid
/var/run/nopeid-install.lock
```

The installer downloads and verifies release artifacts as the invoking user, then
uses `sudo` only for the privileged system install phase. Production installs do
not accept custom install roots.

When `/usr/local/bin` is root-owned and not writable by non-root users, the
installer adds `/usr/local/bin/nopeid` as a convenience symlink to the managed
CLI. A fresh terminal can run unprivileged commands through `PATH`:

```sh
nopeid --version
```

For privileged operations, use the root-owned managed CLI path explicitly:

```sh
sudo /opt/nopeid/bin/nopeid start
```

`/opt/nopeid/bin/nopeid start` restarts the production LaunchDaemon
`system/com.nopeid.agent`; `sudo` is required because macOS system LaunchDaemon
control is privileged.

Supported options:

```sh
curl -fsSL https://nopeid.com/install.sh | sh -s -- --yes
curl -fsSL https://nopeid.com/install.sh | env NOPEID_VERSION=v0.1.2 sh
curl -fsSL https://nopeid.com/install.sh | env NOPEID_YES=1 NOPEID_NON_INTERACTIVE=1 sh
curl -fsSL https://nopeid.com/install.sh | sh -s -- --dry-run
```

NopeID requires macOS 26 Tahoe or newer.

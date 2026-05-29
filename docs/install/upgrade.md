# Upgrade

Run the same installer used for first install:

```sh
curl -fsSL https://nopeid.com/install.sh | sh
```

Pinned upgrades use the release version:

```sh
curl -fsSL https://nopeid.com/install.sh | env NOPEID_VERSION=v0.1.2 sh
```

Non-interactive upgrades can opt into confirmation through environment flags:

```sh
curl -fsSL https://nopeid.com/install.sh | env NOPEID_VERSION=v0.1.2 NOPEID_YES=1 NOPEID_NON_INTERACTIVE=1 sh
```

During upgrade, the installer:

1. Acquires `/var/run/nopeid-install.lock`.
2. Stops production and dev LaunchDaemons.
3. Stops the root agent and helper.
4. Terminates remaining known NopeID agent/helper processes.
5. Stages the new version under `/opt/nopeid/versions/<version>`.
6. Updates `/usr/local/bin/nopeid` to the managed CLI when `/usr/local/bin`
   is root-owned and not writable by non-root users.
7. Rewrites the LaunchDaemon to the fixed production path.
8. Starts the updated service unless `--no-start` is used.
9. Verifies launchd loaded, the agent is alive, and `nopeid --version` matches.

If the production health check fails, the installer restores the previous
version and previous LaunchDaemon plist, then restarts the previous version
unless `--no-start` was used.

The helper can start a confirmed update through the root agent when trusted
release metadata is available.

After install or upgrade, restart the production agent with the root-owned
managed CLI path:

```sh
sudo /opt/nopeid/bin/nopeid start
```

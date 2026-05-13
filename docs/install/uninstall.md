# Uninstall

Remove managed binaries and LaunchDaemons:

```sh
curl -fsSL https://nopeid.com/install.sh | sh -s -- --uninstall
```

Keep user and system data:

```sh
curl -fsSL https://nopeid.com/install.sh | sh -s -- --uninstall --keep-data
```

Remove system data and logs:

```sh
curl -fsSL https://nopeid.com/install.sh | sh -s -- --uninstall --purge-system
```

Uninstall stops production and dev LaunchDaemons, stops the agent/helper, and
terminates remaining known NopeID processes before removing managed files.

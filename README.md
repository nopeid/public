<p align="center">
  <img src="tray-lightmode.png" alt="NopeID logo" width="96">
</p>

# NopeID

**Secure your AI agent runtime.**

NopeID gives you visibility and control over AI agents on your endpoints.
Discover shadow AI, protect reasoning, and block risky behavior in real time.
100% on-device, privacy-first, and free for personal use.

[Website](https://nopeid.com) · [Install](docs/install/installation.md) · [Releases](https://github.com/nopeid/public/releases) · [Contact us](mailto:sales@nopeid.com)

## Quick Install

Install NopeID on macOS with one command.

```sh
curl -fsSL https://nopeid.com/install.sh | sh
```

Then start the NopeID agent:

```sh
sudo nopeid start
```

NopeID currently supports **macOS 26 Tahoe or newer**. Windows and Linux are
coming soon.

## Protection

### Guard the agent before it acts

Check reasoning, launch context, memory state, intent, and commands before risky
activity reaches the machine.

- **Anomaly Detection**: detect behavior that does not match the agent's expected
  task or session pattern.
- **Skill Injection**: catch unauthorized capabilities entering the agent
  runtime.
- **Memory**: watch persisted context for unsafe or unexpected changes.
- **Launch Safety**: validate how an agent starts before giving it room to act.
- **Intent**: compare actions against the task the agent is meant to complete.
- **Risky Commands**: flag destructive, privileged, or suspicious terminal
  actions.

## Runtime

### Choose the execution boundary

Run agent activity in the right runtime for the task, from native host controls
to hostless or remote execution.

- **Journaling and audit**: record runtime actions for review, traceability, and
  compliance.
- **No sandbox running on host**: keep untrusted execution off the user's
  machine.
- **Native sandboxing**: apply local policy controls for desktop agents.

## Enforcement

### Stop unsafe work in real time

Apply policy while the agent is acting, then suspend, kill, or quarantine when
risk crosses the line.

- **Human approval**: require a trusted person before sensitive actions
  continue.
- **Real-time action enforcement**: apply policy as behavior happens.
- **Suspend or kill**: pause unsafe activity or terminate risky processes.
- **Quarantine**: contain affected sessions for review.

## Enterprise

### Secure every AI agent before it acts

Deploy NopeID across your organization with custom scanners, fleet policies,
audit reporting, procurement support, and controls for larger teams.

- Custom scanners for tools, repos, secrets, and workflows.
- Central policy management for approvals, runtime boundaries, and enforcement.
- Enterprise reporting for audit trails, risk events, and control outcomes.
- Team access controls for seats, roles, and administrative access.

[sales@nopeid.com](mailto:sales@nopeid.com)

## On-Device By Design

Your data stays local.

- Product analytics payloads do not include raw commands, prompts, file paths,
  file contents, credentials, usernames, emails, account identities, or IP
  address fields.
- Product analytics can be disabled.
- Enforcement, trust scoring, approvals, and protected runtime data stay on the
  machine.

## Documentation

- [Installation](docs/install/installation.md)
- [Upgrade](docs/install/upgrade.md)
- [Uninstall](docs/install/uninstall.md)

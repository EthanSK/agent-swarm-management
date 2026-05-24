# Agent Swarm Management Release

## Install

- **macOS:** Download `Agent-Swarm-Management-latest-mac-universal.zip`, unzip it, and drag `Agent Swarm Management.app` to Applications.

## Auto Updates

- Sparkle reads `appcast.xml` from the latest GitHub release.
- The appcast and update archive must be signed with the Sparkle EdDSA key whose public half is embedded in `Resources/Info.plist.template`.
- GitHub Actions secret required: `SPARKLE_PRIVATE_KEY`.


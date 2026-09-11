# Security Policy

CodexMulti is an independent open-source project and is not affiliated with or endorsed by OpenAI.

## Supported versions

Only the latest released version receives security updates.

| Version | Supported |
| --- | --- |
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

Use [GitHub Private Vulnerability Reporting](https://github.com/moonsunkim/codexmulti/security/advisories/new). Open this repository's **Security** tab, choose **Report a vulnerability**, and submit the private report there. Do not open a public issue for a suspected vulnerability.

Include the affected version, impact, reproduction steps, and any safe supporting material. Do not include credentials, tokens, or complete copies of `auth.json` or `config.toml`.

We aim to acknowledge a report within 72 hours. We will coordinate validation and remediation privately, then announce the fix through a release.

## Security model

- Credentials stay on the Mac.
- The bundled proxy listens on loopback only.
- CodexMulti has no telemetry or analytics.

## Scope

Examples that are in scope include:

- Exposure of credentials or account data caused by CodexMulti.
- Proxy traffic becoming reachable beyond loopback.
- Authentication or routing behavior that crosses CodexMulti account boundaries unexpectedly.
- Unsafe changes to files or services managed by CodexMulti.

Examples that are out of scope include:

- The behavior of Codex itself when a user explicitly configures it with `danger-full-access`.
- Vulnerabilities in OpenAI or ChatGPT services that are not caused by CodexMulti.
- Unsupported modifications, repackaged builds, or operating systems other than Apple Silicon macOS 26 or later.
- Reports that describe only expected local access by the signed-in macOS user.

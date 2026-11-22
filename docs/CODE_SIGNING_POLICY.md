# Code signing policy

## Current status

DriverLoom has reviewed free open-source signing through [SignPath Foundation](https://signpath.org/), but the signing application is on hold. No application has been submitted, no signing account has been created, and no certificate has been provisioned. **Current public and test installers are unsigned.**

If approved, free code signing will be provided by [SignPath.io](https://signpath.io/), with the certificate issued to [SignPath Foundation](https://signpath.org/). This statement describes the intended setup, not a claim that an existing download is signed.

## Maintainer roles

- Committer and reviewer: [SJB-gif](https://github.com/SJB-gif).
- Release signing approver: [SJB-gif](https://github.com/SJB-gif).

The public maintainer identifier is the GitHub handle. Personal email addresses and personal contact details are not part of the public signing policy.

## Signing and verification

Only DriverLoom binaries built from this repository on GitHub-hosted Actions runners will be submitted. Signing will require a maintainer's manual approval and multi-factor authentication, in accordance with the Foundation's terms.

The intended sequence is to sign the native DriverLoom launcher and setup helper, verify them, package them into the single-file NSIS installer, then sign and verify the final installer. Checksums must be generated after signing. Signing the outer installer alone does not sign its bundled executables.

No certificate keys or account credentials belong in this repository. Signed artifacts will be checked with Windows Authenticode before publication. An unsigned build must remain labelled unsigned rather than being presented as a signed fallback.

## Privacy and support

See the [application privacy information](../README.md#privacy) and [support policy](../README.md#support). DriverLoom includes no analytics or automatic diagnostic uploads. Selected update checks contact Windows Update and official manufacturer services.

Code signing does not include an individual user-support service. Reports may not be reviewed or answered. Do not use personal contact channels for app support.

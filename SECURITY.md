# Security policy

Found a vulnerability in Onetime Secret? Email
`security@onetimesecret.com`. Don't open a public issue.

## Supported versions

Support is keyed to the current minor release, not to a fixed list of version
numbers:

| Release line        | Support                                                      |
| ------------------- | ------------------------------------------------------------ |
| Most recent minor   | Full support — new features, bug fixes, and security updates |
| The minor before it | Bug fixes and security updates only                          |
| Anything older      | End of life — unsupported                                    |

Each new minor release shifts every line down one row. At the time of writing
the most recent minor is 0.26.x, which puts 0.25.x in bug-fix-and-security-only
support and 0.24.x and earlier at end of life.
[Releases](https://github.com/onetimesecret/onetimesecret/releases/latest) is
authoritative for what's current.

If you're on an unsupported version, upgrade. That's the only way to get
current security fixes.

## Reporting a vulnerability

Report as soon as you find something. A partial report now beats a polished
one later — you don't need a working exploit, and you don't need to be
certain it's a real issue.

Email `security@onetimesecret.com` with the subject line
`Vulnerability Report: [Brief Description]`, and include as much of this as
you can:

- What the vulnerability is
- Steps to reproduce it
- The impact you think it could have
- How to reach you for follow-up questions

## What to expect

- **Acknowledgment** of your report within 5 business days.
- **Initial assessment** of the vulnerability within 14 business days.
- **Status updates** at least once every 5 business days, and in no case more
  than 7 calendar days apart, until the issue is resolved or we've made a
  decision.

We don't currently operate a paid bounty program, but we're open to
discussing rewards case by case for significant vulnerabilities.

## Resolution

If we accept the report, we work on a fix, aim to release it as soon as
possible, and tell you once it's deployed. If we decline it, we explain in
detail why.

## Confidentiality

We use encrypted email (ProtonMail). Reports are kept confidential, and we
work with you to make sure no details of the vulnerability are disclosed
until a fix is in place.

Thank you for helping keep Onetime Secret secure.

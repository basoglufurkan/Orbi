# Security policy

## Supported versions

Security fixes go into `main` and ship in the next App Store release. Please
check that a problem still exists on the latest version before reporting it.

## Reporting a vulnerability

Please don't open a public issue. Report it privately instead:

1. On GitHub, open the repository's **Security** tab and choose **Report a
   vulnerability**, or
2. use the contact form at [mobapptech.com/#contact](https://www.mobapptech.com/#contact).

Include what you found, the steps to reproduce it, what an attacker could do
with it, and the app version or commit. We aim to reply within a week, and
once it's fixed we'll credit you if you'd like.

## Scope

Orbi has no server of its own. Useful areas to look at:

- data on the device and in the person's private iCloud database;
- Focus together rooms in the public CloudKit database, and their join codes;
- deep links and universal links (`lumora://`, `www.mobapptech.com/lumora/`);
- App Intents, widgets and other entry points that change app state.

The RevenueCat public SDK key and the Firebase configuration ship inside every
copy of the app and are public by design; they aren't vulnerabilities on their
own.

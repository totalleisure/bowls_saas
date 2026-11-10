# App registration email alerts

Implemented and deployed in staging first, then production on 27 October 2026. No Flutter/store release required: existing Apps use the updated registration endpoint. No commits or pushes.

Every successful self-registration queues an operational email to the platform mailbox and one to the selected Club's recorded Membership Secretary. Subject includes Club and member name; body includes Club, name, email, telephone, UK registration time and Guest App role clarification. No password, full postal address or authentication secret is included. These operational alerts are independent of newsletter subscriptions.

Production destination is bowls@totalleisure.com. The hosting account could not change Edge secrets, so the public destination is specified in register_member/mailbox_config.ts. Staging's corresponding constant is null, retaining its configured REGISTRATION_ALERT_EMAIL/MS_MAILBOX destination. This is the only intentional environment-specific source difference in these registration files. Existing sender configuration and credentials were not changed.

Membership Secretary comes strictly from the selected Club's single home venue club_officers.membership_secretary.email. No fallback to Club Secretary. A missing secretary, blank editor fields, missing/invalid email, or ambiguous home-venue configuration is explained in the platform email. Secretary email does not require an App profile. Identical platform/secretary addresses receive one combined notification. The existing secretary in-App alert is retained where an active Club profile matches the recorded address, without generating a duplicate email.

Membership creation/activation and notification queue inserts now share a service-only transaction. A private membership-keyed ledger suppresses repeated alerts. All registration completion routes use it: new account, existing account joining another Club, claimed orphan profile, and rebuilt profile. Already registered requests remain rejected without new alerts. The original account creation, password handling, cleanup and Guest role behavior remain otherwise unchanged.

Migration mappings:

| Amendment | Source / staging | Production ledger |
|---|---|---|
| app_registration_alerts | 20261027231828 | 20261027232208 |
| clarify_empty_registration_officer | 20261027232114 | 20261027232210 |

Final deployed complete_app_guest_registration definition hash in both databases: a12e6e9d4fa23de38b1a5270092711a0. Production register_member v13 retains JWT verification. Downloaded deployed files verified against source. Production worker v12 prior source retained in registration-worker-before.json; restore that endpoint before disabling the new RPC. Retain private notice records for audit after real registrations.

Validation: eight mocked endpoint tests pass in both checkouts. Rolled-back SQL tests pass in both databases for service-only access, missing/invalid/blank secretary, strict role routing, two recipients, same-address deduplication, repeated requests, and new membership plus alerts. No test accounts or emails persisted, and no email worker was invoked by tests. Shared Dart source comparison passes. All unrelated changes and environment credentials remain untouched.

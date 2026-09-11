# Release status — 11 September 2026

The nullable Title/Outdoor Club migration has been applied and the actual schema verified. All three optional columns accept NULL with no defaults. Following explicit user approval, import_members_csv version 26 was deployed and its downloaded source matched the local reviewed source.

Live non-import checks passed: OPTIONS 200, unsigned POST 401, invalid-session POST 401. No CSV was uploaded or imported and no member account was created by these checks. The Flutter release web build succeeded in build/web. Use the rebuilt application, which asks for Active/Inactive before uploading; an older app without that question is not compatible with this importer.

The historical local-review notes below predate this approved deployment. No commit or push has been performed. The committee imports remain user-operated.

---
# Membership import — corrected local review

Prepared in C:\src\bowls_saas. No CSV was uploaded or imported. No production records were changed. No deployment, commit or push was performed.

## Behavior ready for review

- Every import asks whether **new memberships** start Inactive or Active. Inactive is the default each time. Cancel stops before upload.
- New memberships always receive the Member role. CSV/request role overrides are ignored.
- Existing memberships retain their role and active status, even if the next import selects a different starting status. The database conflict operation does not update existing memberships.
- New accounts require a CSV password in either mode. This importer does not send invitation emails. Existing accounts do not require a password to be supplied again, and their passwords are not changed.
- Title, Gender and Outdoor Club remain optional. Blank CSV fields never erase populated profile values. Explicit editor clearing saves NULL. Ambiguous gender stays unsupplied and is reported for review, never inferred.
- Display names are supplied when Auth automatically creates a profile. Existing email-placeholder or empty display names are repaired from the retained first/last names. Custom display names are preserved.
- The completion dialog separates new memberships from existing memberships preserved, so repeat-import results can be checked accurately.

## Permission correction

The Edge Function verifies the bearer token through Auth, then checks the actual database for platform-superuser status or an active administrator membership in the selected club. Client-supplied roles and user metadata are not trusted for authorization. The uploaded CSV path must belong to that club's folder. No CSV download, account listing or mutation happens before these checks. Permission-query failures deny the request.

Browser preflight is handled without accessing member data. Only POST performs imports. These checks are inside the function and do not rely on the gateway's JWT setting. The existing live function remains unchanged until a separately approved release.

## Tests performed locally

- **31 Edge Function tests passed**, executing the actual handler with offline Auth/storage/database mocks.
- **11 Flutter membership tests passed**: status-choice dialog, optional field loading/saving/clearing, and existing visibility tests.
- Focused Flutter analysis: no errors or newly introduced notices; 10 existing warnings/informational notices remain across the two pre-existing screens. The new dialog and new dialog tests have no analysis findings.
- Tracked and new-file whitespace checks passed.

The Edge Function test model uses distinct user/profile/membership IDs, enforces query filters and conflict keys, and models the inspected automatic profile-creation trigger. Its staged test verifies:

| Submission | New accounts | New memberships | Existing memberships retained |
|---|---:|---:|---:|
| First two | 2 | 2 | 0 |
| Repeat same two, selecting the other status | 0 | 0 | 2 |
| All nine | 7 | 7 | 2 |

Additional tests cover both initial statuses, role preservation, duplicate emails, missing/ambiguous optional fields, missing contacts, password requirements, unauthorized callers, another club's CSV path, permission lookup failure, malformed CSV, profile failure reporting and account-list pagination.

These are local simulations, not real imports. Deno is not installed locally: the Node tests strip TypeScript and run the handler with mocks; they are not Deno type checking or live Supabase integration tests. Deployment validation remains necessary before release.

## Pending release decisions

1. Review these corrected changes. No deployment is authorized by completing this local work.
2. If approved later, apply `20260910211848_add_optional_member_title_outdoor_club.sql` before the updated app/function use the new columns. It adds nullable `title` and `outdoor_club` text columns without defaults. The existing nullable `gender` constraint is retained.
3. Release the corrected Edge Function before allowing use of the updated app. The app sends a required boolean `new_members_active`; old requests lacking a choice are rejected safely. The old deployed function does not understand this setting, so do not use the updated app with the old function.
4. After a separately approved release, the user will import the chosen two committee records, repeat those two, then import all nine. The assistant will not perform these imports.

The committee CSV has nine records, no duplicate emails, and no missing emails/passwords. Four names remain unmatched by exact first-name/surname comparison with the authoritative workbook: Dave Hever, Steve Hill, Kay Langston and Carol Watt Sullivan. Review their identity/source matching individually before importing the complete file; do not guess aliases or invent optional values.

## File layout

`supabase/functions/import_members_csv/index.ts` is the Edge Function source. `supabase/migrations/procedures/import_members_csv.sql` is a synchronized copy retained for review, but it contains TypeScript and must not be executed as SQL. The migration at the root of `supabase/migrations` is the actual SQL schema change. Source workbooks/CSVs and the historical text export under `Supabase Configuration` were not modified.

## Follow-up: Gender, Sex at birth and editor wording

Explicit Male/Female CSV values now fill both gender and sex_at_birth, as requested by the club. Other/blank values do not populate sex_at_birth. Existing populated values remain protected on re-import. No migration is required for the existing sex_at_birth column. The updated importer has 40 passing offline tests, including filling a missing sex_at_birth value on re-import and preserving a populated one.

Outdoor Club is now in Player details, before Preferred Player Position. Email help now says: To change your email address, open Member and Volunteer Lists, then select Account and Security. Choose Change login email and follow the steps shown.

The three editor tests and whitespace checks pass. Deployment of this follow-up is pending explicit approval; no CSV imports were performed.

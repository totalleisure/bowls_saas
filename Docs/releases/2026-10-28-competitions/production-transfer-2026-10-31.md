# Production competitions transfer — 31 October 2026

## Completed

User authorised transfer of all reviewed staging draws and creation of Keith Stone as captain-managed. When reconciliation found Evan Jones absent from production, user separately authorised creating him too. Both were created through the existing captain-managed RPC, with no Auth account or email. Keith has the user-supplied provisional number 07710 987654, still awaiting verification; Evan uses his recorded staging phone. Production member IDs differ from staging for these records and earlier mapped identities; no credentials or staging synthetic Auth users were transferred.

Transferred six LCPIBC competition records, 128 entries, 176 entry-member links, 22 rounds and 188 match records. No recorded result events or linked fixtures existed in the snapshot. Ladies Club Bowler and Ladies Singles Championship currently have no entries or draws; the four other competitions contain the populated draws. All competitions retain draft status. Entry order, partnerships, paid/handicap values, dates, settings, sources and existing bye advancement preserved. Unicode season separators corrected after full-data verification caught an encoding-only transfer issue.

Production installed seven existing reviewed competition migrations, then both environments received corrective migration 20261031140916_normalize_competition_draw_messages to normalize draw error-message encoding. All 17 live competition function definitions now match by server-generated hash after CRLF normalization. Component migration versions are recorded in production. Production additionally has orchestration migration entries from the connector apply operations; ledger history is not identical to staging and was not rewritten.

Promoted nine reviewed Dart files (competition feature and picker/navigation integration), Noto font assets, targeted pubspec font declaration, migration sources and competition tests into C:/src/bowls_saas. Preserved entry points, project IDs, secrets, mailbox configuration and unrelated working changes. Shared Dart comparison passes. Recovery source backups and private before/after/mapping snapshots are under gitignored tmp/member-sync*; prior function definition snapshots are retained. No commits, pushes, version bumps or store submissions.

## Verification

All transferred records compare exactly to the mapped staging snapshot, including rules/season/date text. Hosted rolled-back regression passes in staging and production: submission, explicit confirmation, progression, audit, Club RLS, denied ordinary-member/cross-Club changes and no fixtures. David Singer's actual production identity has admin access and can read all six competitions. 27 competition tests passed in C:/src/bowls_saas. Windows release build succeeded in C:/src/bowls_saas/build/windows/x64/runner/Release. Native runner timestamp can remain older when unchanged; Flutter AOT/assets are rebuilt separately. Database security advisors show expected authenticated SECURITY DEFINER exposure for guarded RPCs, not anonymous competition mutation grants.

## Operational status

No competition emails or notifications were sent or queued. Player-email template/test allowlist is still a non-sending staging prototype; delivery workflow not deployed. Publishing a competition changes member visibility and enables result entry, but currently does not email players. Review then publish each draw explicitly. Production database and local source/build are ready; installed store clients have NOT been updated. David needs the updated client to see the competition screens. Physical A3 printing still awaits user verification.

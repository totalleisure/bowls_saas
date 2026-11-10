# Keep Fixture List position after details

The Fixture Details return path previously called the full List reload. It now fetches only the opened fixture (same projection and Club scope) and that member's published selection badges for this fixture. The existing scroll controller, loaded date range, filters, search and other entry maps remain in place. Stable card keys preserve identity when an entry is removed or reordered.

Only the corresponding entry is replaced if changed. A deleted/inaccessible fixture or one moved outside loaded dates is removed. Existing sorting/search/filter rules apply to updated data. The current scroll offset is restored after layout, bounded by the remaining content extent. A failed refresh leaves the list usable and reports the failure without a full reload. Personal badge lookup failures retain previous badges except cancelled fixtures, whose badges are cleared.

Verified in staging before promotion: 23 diary, personal involvement and return tests passed. The same 23 passed in production. Changed-file analysis clean in both; Compare-AppSources passed. Coverage includes no full reload on return, retained controller and pixel offset, unchanged neighbouring entries, updated/cancelled/deleted/moved fixtures, lookup failures, and Club/member/fixture query scopes.

An initial production promotion was automatically rejected because an older failed mock-response test log was still present. After fixing the mock's missing request reference, the original staging log was refreshed with all 23 passes and promotion was approved. No failed verification was bypassed.

Only three shared Dart files and the new regression test were promoted. No database, Edge function or store deployment, commit, push or version change. Restart the local production Flutter process to review the change; installed store Apps need a future release.

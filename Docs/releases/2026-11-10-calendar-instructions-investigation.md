# Calendar import instructions and duplicate investigation

Staging and production email workers now instruct recipients to tap the calendar attachment's name/icon to open its preview, tap Add To Calendar, then choose a calendar if prompted and confirm once. Acceptance remains a separate response. Previously delivered emails are unchanged. The event-title separator is ASCII to avoid encoding differences during deployment.

Verified in staging before promotion. All 15 calendar/action/worker-authentication tests pass in both checkouts. Shared Dart comparison passes. Production worker version 21 is active and all five deployed files were verified against reviewed source. No database or client/store deployment is required. Existing worker credentials and gateway settings are preserved.

Investigation of the 12 November 2026 14:00–16:30 staging fixture fccc2d64-bdd1-4755-8118-ce989076f103 found two selection emails: one to wayne.sayers@icloud.com at 00:00:04 UTC, another to wayne@totalleisure.com at 00:00:05 UTC on 10 November. Each has one recorded send attempt and one saved PDF attachment. The worker adds exactly one ICS containing one VEVENT per actionable outbound email; no calendar account selection, attendee, scheduling request, or calendar-write API is used. A later acceptance notification has no action block and receives no ICS.

These records establish two recipient emails, not two calendar writes or two user imports. The duplicate's precise cause remains unconfirmed. Requested the mail app and the names/accounts of the two destination calendars to distinguish separate imports from synchronization/display behavior. No calendar records were removed, no emails resent, and no unsupported prevention change was made.

Apple documents that the same ICS event can exist in multiple calendars: https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemexternalidentifier . Duplicate-display guidance: https://support.apple.com/en-gb/102180 . Neither establishes the cause on this device.

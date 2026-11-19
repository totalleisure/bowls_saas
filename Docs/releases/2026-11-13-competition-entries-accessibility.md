# Competition Entries: Windows accessibility tooltip anchors

The supplied Windows debug log contained 1,681 native `Failed to update ui::AXTree` messages across five orphan-node IDs. No Dart exception or database failure appeared in that log. The user identified Competition Entries as the triggering screen.

A regression test reproduced an attached tooltip overlay with no matching accessibility traversal parent on the actual Entries screen before the fix. Each entry control is now given its own Semantics container, preventing sibling tooltip OverlayPortal anchors from merging inside an IndexedSemantics list item. Tooltips, screen-reader labels and control behaviour remain enabled. No SDK, native engine or global accessibility switches are modified.

The test hovers between Replace player, handicap, edit and remove controls in draft entries and between the available controls in published entries. It checks tooltip visibility, retained parent/child anchors, Paid accessibility text and cleanup after dismissal. Thirteen focused tests passed in staging, including existing replacement, handicap and preliminary flows. Verification is of the reproduced semantics-tree failure; the Windows native bridge should be retested by fully restarting the App, since hot reload retains the corrupted native window.

Reference: https://github.com/flutter/flutter/issues/182444 and the traversal-parent analysis at https://github.com/flutter/flutter/pull/190344. Local Flutter SDK: 3.44.9. This is a narrow App workaround, not an upstream SDK fix.

No database or email changes, data edits, release-number changes, commits or store upload are part of this amendment. Staging is verified first and the same reviewed amendment is promoted to production; existing unrelated working changes are preserved.

Promotion checks: thirteen focused tests passed in each source tree; Compare-AppSources.ps1 reports matching shared Dart sources. Staging Windows Release build passed. Production Windows Release build is checked before delivery. The native Windows session itself still needs a full restart and user retest.

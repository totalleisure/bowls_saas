# Declined-player recruitment correction — 18 October 2026

The existing availability confirmation checked RSVP `no`, but missed a subsequent team-selection decline. The pool-add operation then left the decline intact, so the new declined-player filter hid the member again after reporting success.

The same confirmation flow now checks both refusal types. Confirming a removed player's recruitment atomically resets their selection response to pending, keeps them unselected, and restores their eligible RSVP pool entry. This is not acceptance; they must respond again if subsequently selected. Cancellation makes no writes. Existing unavailable-RSVP overrides remain administrator-only. The audit journal retains the former decline. Pool resets do not generate team-response notifications.

Verification: 292 staging Flutter tests passed (4 existing skips); 8 targeted production tests passed. Staging rollback tests cover unconfirmed refusal, confirmed persistent pool return, preserved teammates, no queued messages and unauthorized rejection. The deployed functions match in both databases. Security advisors report no new findings. The older RPC remains available but cannot silently bypass the decline confirmation.

Manual staging check: re-add the removed declined test player, cancel once, confirm the second time, then refresh and reopen the team. They should remain in the available pool, not automatically in the selected team. Next test Reserves / Remove / Cancel with an unallocated selected player; a fully allocated team plus existing reserves must not show that dialogue.

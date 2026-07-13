**team_management_review.md**

1. Team Creation

Create Team Selection

 Create empty team selection.
 Add selected players.
 Add reserves.
 Remove selected players.
 Promote reserve to player.
 Demote player to reserve.
 Confirm before reserve promotion.
 Confirm before reserve demotion if assigned.
 Warn if unavailable player selected.
 Preserve acceptance status.

2. Team Positions

Assign Players

 Assign player.
 Move player.
 Swap player.
 Clear position.
 Save incrementally.
 Server-side transaction.
 Duplicate player prevention.
 Reserve promotion handled.
 Acceptance colours.
 Picker colours.
 Team/Position shown in picker.
 Ready to publish indicator.

3. Validation Before Publish

Mandatory
 Every selected player allocated.
 Or marked reserve.
 No duplicate assignments.
 Team assignment saved.

Optional Override
 Missing team positions.
 Captain confirmation.
 Publish anyway.

4. Communications Review

This is where I think we now need to slow down.

Rather than coding, let's design.

Event	App	Email	Team Sheet	Status
Publish Team	?	?	?	    Review
Publish Incomplete	?	?	?	Review
Reserve Promoted	?	?	?	Review
Player Removed	?	?	?	    Review
Reminder Pending	?	?	✖	Review
Reminder Filtered	?	?	✖	Review
Fixture Cancelled	?	?	?	Review
Fixture Changed	?	?	?	    Review
Team Updated	?	?	?	    Review

5. Production Readiness

Reliability
 
 Transactional RPCs.
 Server validation.
 Client validation.
 Confirmation dialogs.
 Local state updates.
 Reduced screen reloads.

6. UI Polish
 
 Team Pool retained.
 Selected list retained.
 Position picker enhanced.
 Status summary.
 Ready to publish.
 Final visual review.
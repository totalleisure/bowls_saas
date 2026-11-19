# Apple distribution status, 19 November 2026

Verified directly through the App Store Connect API using the configured key on the signing Mac. This inspection made GET requests only. No rebuild, binary upload, duplicate review submission or publication request was made.

- App: Total Leisure Bowls, com.totalleisure.bowlssaas, Apple app ID 6762380407.
- Existing processed build: 1.6.8 (34), build ID 3038c3df-f4dd-4fd1-a382-d7dc637ec4ad, processingState VALID, not expired.
- Public iPhone version 1.6.8: WAITING_FOR_REVIEW, releaseType AFTER_APPROVAL. Version ID 4401119e-2e68-4f82-a814-82457d9304f0. Its selected build is the same build 34. Public availability requires Apple's approval. The API currently reports 1.6.6 (32) as the live version; earlier reports that 1.6.8 was available were not confirmed by this check.
- TestFlight: internalBuildState IN_BETA_TESTING, externalBuildState WAITING_FOR_BETA_REVIEW, autoNotifyEnabled true. The existing beta review submission is WAITING_FOR_REVIEW; it was submitted with the previous manual upload.
- External group LCPIBC Testing, ID 8f12a7da-7593-48b0-a1c2-428f0590124d, already includes build 34. User has been asked whether this is their sub-committee team; do not create another group or redistribute to a different audience without identifying it.
- Internal group Bowls_Distribution has access to all builds. No group membership or tester permissions were changed.
- Existing en-GB TestFlight testing notes are present. They describe the booking, weekend rules and diary checks. No notes were changed during this inspection.

The user's request is TestFlight preview for the sub-committee and public Apple publication. Both existing review submissions are already queued. Do not cancel/re-submit them merely to perform the request again. After approval, public release is automatic; external TestFlight availability remains subject to Apple's beta review.

No database, application source, credential or keychain changes were made.

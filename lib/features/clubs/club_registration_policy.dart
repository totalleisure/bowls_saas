/// Registration decisions shared by the preview tests and future server contract.
/// This is not an authorisation boundary: production must verify every input server-side.
enum ClubLookupResult { found, notFound, unavailable }

enum ManualClubDecision { pending, approved, declined }

enum ClubRegistrationDecision {
  verifyEmail,
  alreadyRegistered,
  contactUs,
  declined,
  retryLookup,
  proceed,
}

ClubRegistrationDecision clubRegistrationDecision({
  required ClubLookupResult lookup,
  required bool duplicate,
  required bool emailVerified,
  ManualClubDecision manual = ManualClubDecision.pending,
}) {
  if (duplicate) return ClubRegistrationDecision.alreadyRegistered;
  if (manual == ManualClubDecision.declined) {
    return ClubRegistrationDecision.declined;
  }
  if (lookup == ClubLookupResult.unavailable) {
    return ClubRegistrationDecision.retryLookup;
  }
  if (lookup == ClubLookupResult.notFound &&
      manual != ManualClubDecision.approved) {
    return ClubRegistrationDecision.contactUs;
  }
  if (!emailVerified) return ClubRegistrationDecision.verifyEmail;
  return ClubRegistrationDecision.proceed;
}

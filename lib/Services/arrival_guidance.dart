/// Prefer captain-written arrival guidance to the standard reminder.
/// This deliberately recognises wording as well as numeric times: "arrive early",
/// "meet at the club", and "report to reception" all override the default.
bool hasArrivalGuidance(String? instructions) {
  final text = (instructions ?? '').toLowerCase();
  return RegExp(r'\b(arriv(?:e|es|ing|al)|meet(?:ing)?|report\s+(?:at|by|to)|check[ -]?in|be\s+(?:there|at\s+the\s+(?:club|venue)))\b')
      .hasMatch(text);
}

String? defaultArrivalGuidance(String? instructions) => hasArrivalGuidance(instructions)
    ? null : 'Please arrive at least 30 minutes before the start of the fixture';

/// Compare actual instants, without applying the club's display-time offset.
String fixtureCountdown(String timestamp, {required DateTime now}) {
  final diff = DateTime.parse(timestamp).toUtc().difference(now.toUtc());
  if (diff.isNegative) return '0 mins time';
  if (diff.inDays >= 2) return '${diff.inDays} days time';
  if (diff.inDays == 1) return '1 day time';
  final hours = diff.inHours;
  final minutes = diff.inMinutes.remainder(60);
  if (hours > 0) {
    return '$hours ${hours == 1 ? 'hour' : 'hours'} $minutes mins time';
  }
  return '$minutes mins time';
}

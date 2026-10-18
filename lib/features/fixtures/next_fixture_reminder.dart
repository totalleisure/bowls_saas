import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/fixture_countdown.dart';
import '../../core/utils/fixture_reminders.dart';
import '../../core/utils/hex_color.dart';
import '../../services/venue_actions_service.dart';
import '../fixtures/fixture_display.dart';

/// Shared next-match reminder for every club starting screen.
class NextFixtureReminder {
  final BuildContext context;
  final String clubName;
  final Map<String, dynamic>? nextMatch;
  final Map<String, dynamic>? secondMatch;
  final List<Map<String, dynamic>> fixtures;
  final int rsvpCount;
  final Future<void> Function(String) openFixture;
  final Map<String, dynamic>? Function(Map<String, dynamic>)? venueResolver;
  final Widget Function(Map<String, dynamic>, Color)? travelBuilder;
  final DateTime Function()? now;
  NextFixtureReminder({
    required this.context,
    required this.clubName,
    required this.nextMatch,
    required this.openFixture,
    this.secondMatch,
    this.fixtures = const [],
    this.rsvpCount = 0,
    this.venueResolver,
    this.travelBuilder,
    this.now,
  });

  String _timeUntilFixture(String timestamp) =>
      fixtureCountdown(timestamp, now: now?.call() ?? DateTime.now());
  Map<String, dynamic>? _physicalVenueForFixture(
    Map<String, dynamic> fixture,
  ) =>
      venueResolver?.call(fixture) ?? VenueActionsService.fixtureVenue(fixture);
  Widget _buildFixtureTravelActions({
    required Map<String, dynamic> fixture,
    required Color foregroundColor,
  }) {
    if (travelBuilder != null) return travelBuilder!(fixture, foregroundColor);
    final venue = _physicalVenueForFixture(fixture);
    if (venue == null || !VenueActionsService.canNavigate(venue)) {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      onPressed: () =>
          VenueActionsService.navigate(context: context, venue: venue),
      icon: const Icon(Icons.navigation_outlined),
      label: const Text('Navigate'),
    );
  }

  Color? _fixtureTypeBackgroundColor(Map<String, dynamic> fixture) {
    final competitionType =
        fixture['competition_type'] as Map<String, dynamic>?;
    final colourScheme =
        competitionType?['colour_scheme'] as Map<String, dynamic>?;

    if (colourScheme == null) return null;

    return colorFromHex(
      colourScheme['background_hex']?.toString(),
      fallback: Colors.grey.shade100,
    );
  }

  Color? _fixtureTypeForegroundColor(Map<String, dynamic> fixture) {
    final competitionType =
        fixture['competition_type'] as Map<String, dynamic>?;
    final colourScheme =
        competitionType?['colour_scheme'] as Map<String, dynamic>?;

    if (colourScheme == null) return null;

    return colorFromHex(
      colourScheme['foreground_hex']?.toString(),
      fallback: Colors.black87,
    );
  }

  Future<void> show() async {
    if (!context.mounted) return;

    final reminders = fixtureReminders([
      ?nextMatch,
      ?secondMatch,
      ...fixtures,
    ], now: now?.call() ?? DateTime.now());
    final fixture = reminders.isEmpty ? null : reminders.first;

    if (fixture == null) {
      if (rsvpCount == 0) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Next match'),
            content: const Text(
              'You have no upcoming accepted matches or responses due within seven days.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Colors.lightBlue.shade50,
          title: const Text('Fixtures available'),
          content: Text(
            rsvpCount == 1
                ? 'You have 1 fixture available to Sign Up to (RSVP).\n\n'
                      'If you wish to play, click the fixture and select your availability.'
                : 'You have $rsvpCount fixtures available to Sign Up to (RSVP).\n\n'
                      'If you wish to play, click a fixture and select your availability.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      return;
    }

    final isCancelled = fixture['cancelled_at'] != null;

    final bg = isCancelled
        ? Colors.grey.shade300
        : (_fixtureTypeBackgroundColor(fixture) ?? Colors.white);

    final fg = isCancelled
        ? Colors.grey.shade800
        : (_fixtureTypeForegroundColor(fixture) ?? Colors.black87);

    final title = fixtureTitleUnified(fixture, myClubName: clubName);

    final startsIn = _timeUntilFixture(fixture['start_at'].toString());

    final startAt = parseClubTime(fixture['start_at'].toString());

    final formattedStart = DateFormat(
      'EEEE d MMMM yyyy • HH:mm',
    ).format(startAt);

    final venue = _physicalVenueForFixture(fixture);
    final venueName = VenueActionsService.text(venue?['name']);
    final address = venue == null ? '' : VenueActionsService.address(venue);

    final hasVenue = venueName.isNotEmpty || address.isNotEmpty;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: bg,
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isCancelled) ...[
                        Text(
                          'CANCELLED',
                          style: TextStyle(
                            color: Colors.grey.shade900,
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'This fixture was due in $startsIn',
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ] else
                        Text(
                          fixture['_reminderAcceptance'] == 'pending'
                              ? 'Response needed • Match in $startsIn'
                              : 'Your next match is in $startsIn',
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w800,
                            fontSize: 26,
                          ),
                        ),

                      const SizedBox(height: 18),

                      Text(
                        title,
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(formattedStart, style: TextStyle(color: fg)),

                      if (!isCancelled) ...[
                        const SizedBox(height: 14),
                        Text(
                          (fixture['notes'] ?? '').toString().trim().isEmpty
                              ? 'Special instructions: none at the moment'
                              : 'Special instructions: ${fixture['notes'].toString().trim()}',
                          style: TextStyle(color: fg),
                        ),
                      ],

                      if (hasVenue) ...[
                        const SizedBox(height: 18),
                        Text(
                          'Location',
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),

                        if (venueName.isNotEmpty)
                          Text(
                            venueName,
                            style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                        if (address.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(address, style: TextStyle(color: fg)),
                        ],

                        if (!isCancelled) ...[
                          const SizedBox(height: 12),
                          _buildFixtureTravelActions(
                            fixture: fixture,
                            foregroundColor: fg,
                          ),
                        ],
                      ],

                      const SizedBox(height: 18),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(dialogContext);

                              await openFixture(
                                fixture['id']?.toString() ?? '',
                              );
                            },
                            child: Text(
                              !isCancelled && fixture['_reminderAcceptance'] == 'pending'
                                  ? 'Review and respond'
                                  : 'View fixture',
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Text('OK', style: TextStyle(color: fg)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              for (final upcoming in reminders.skip(1))
                _buildSecondMatchPopupCard(upcoming),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondMatchPopupCard(Map<String, dynamic> fixture) {
    final isCancelled = fixture['cancelled_at'] != null;

    final bg = isCancelled
        ? Colors.grey.shade300
        : (_fixtureTypeBackgroundColor(fixture) ?? Colors.grey.shade100);

    final fg = isCancelled
        ? Colors.grey.shade800
        : (_fixtureTypeForegroundColor(fixture) ?? Colors.black87);

    final title = fixtureTitleUnified(fixture, myClubName: clubName);

    final startsIn = _timeUntilFixture(fixture['start_at'].toString());

    final startAt = parseClubTime(fixture['start_at'].toString());

    final formattedStart = DateFormat(
      'EEEE d MMMM yyyy • HH:mm',
    ).format(startAt);

    final venue = _physicalVenueForFixture(fixture);
    final venueName = VenueActionsService.text(venue?['name']);

    return SizedBox(
      width: double.infinity,
      child: Card(
        color: bg,
        elevation: 4,
        margin: const EdgeInsets.only(top: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            Navigator.of(context).pop();

            await openFixture(fixture['id']?.toString() ?? '');
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isCancelled) ...[
                  Text(
                    'CANCELLED',
                    style: TextStyle(
                      color: Colors.grey.shade900,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This fixture was due in $startsIn',
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                  ),
                ] else
                  Text(
                    fixture['_reminderAcceptance'] == 'pending'
                        ? 'Response needed • Match in $startsIn'
                        : 'Also coming up in $startsIn',
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),

                const SizedBox(height: 8),

                Text(
                  title,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                ),

                const SizedBox(height: 6),

                Text(formattedStart, style: TextStyle(color: fg)),

                if (venueName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(venueName, style: TextStyle(color: fg)),
                ],

                if (!isCancelled) ...[
                  const SizedBox(height: 10),
                  _buildFixtureTravelActions(
                    fixture: fixture,
                    foregroundColor: fg,
                  ),
                ],

                if (isCancelled) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Tap to view cancellation details',
                    style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

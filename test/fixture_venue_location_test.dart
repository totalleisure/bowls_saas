import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/services/venue_actions_service.dart';
import 'package:bowls_saas/services/navigation_service.dart';

void main() {
  const lewisham = {
    'id': 'lewisham',
    'name': 'Lewisham',
    'address_line1': 'Westerley Crescent',
    'postcode': 'SE26 5AQ',
  };
  const whiteOak = {
    'id': 'white-oak',
    'name': 'White Oak Indoor Bowls Centre',
    'address_line1': 'White Oak venue address',
    'latitude': 51.4,
    'longitude': 0.2,
  };

  test('away card and actions use White Oak, never our own club', () {
    final venue = VenueActionsService.fixtureVenue({
      'is_home': false, 'venue': whiteOak, 'opponent_venue': lewisham,
    })!;
    expect(venue['name'], whiteOak['name']);
    expect(VenueActionsService.address(venue), 'White Oak venue address');
    expect(venue['latitude'], 51.4);
    expect(venue['longitude'], 0.2);
    expect(VenueActionsService.canNavigate(venue), isTrue);
    expect(NavigationService.googleMapsDirectionsUri(venue)!.queryParameters['destination'], '51.4,0.2');
    expect(NavigationService.wazeDirectionsUri(venue)!.queryParameters['ll'], '51.4,0.2');
  });

  test('home card retains Lewisham playing location', () {
    expect(VenueActionsService.fixtureVenue({
      'is_home': true, 'venue': lewisham, 'opponent_venue': whiteOak,
    }), lewisham);
  });

  test('events and open sessions keep their explicitly selected venue', () {
    for (final mode in ['rsvp', 'open']) {
      expect(VenueActionsService.fixtureVenue({
        'is_home': false, 'venue': whiteOak, 'opponent_venue': lewisham,
        'competition_type': {'uses_rinks': false, 'selection_mode': mode},
      }), whiteOak);
    }
  });

  test('missing or empty playing venue cannot redirect to the other club', () {
    for (final venue in [null, <String, dynamic>{}, 'invalid']) {
      expect(VenueActionsService.fixtureVenue({
        'is_home': false, 'venue': venue, 'opponent_venue': lewisham,
      }), isNull);
    }
    expect(VenueActionsService.fixtureVenue(null), isNull);
  });
}

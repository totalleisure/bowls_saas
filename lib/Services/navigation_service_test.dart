import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/services/navigation_service.dart';

void main() {
  group('NavigationService.googleMapsDirectionsUri', () {
    test('uses Place ID first and requests navigation', () {
      final uri = NavigationService.googleMapsDirectionsUri({
        'name': 'Example Bowls Club',
        'google_place_id': 'place-123',
        'latitude': 51.5,
        'longitude': -0.1,
      });

      expect(uri, isNotNull);
      expect(uri!.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters['api'], '1');
      expect(uri.queryParameters['travelmode'], 'driving');
      expect(uri.queryParameters['dir_action'], 'navigate');
      expect(uri.queryParameters['destination'], 'Example Bowls Club');
      expect(uri.queryParameters['destination_place_id'], 'place-123');
    });

    test('uses coordinates when there is no Place ID', () {
      final uri = NavigationService.googleMapsDirectionsUri({
        'name': 'Ignored Name',
        'latitude': '51.5007',
        'longitude': '-0.1246',
      });

      expect(uri!.queryParameters['destination'], '51.5007,-0.1246');
      expect(uri.queryParameters.containsKey('destination_place_id'), isFalse);
    });

    test('falls back to address and then venue name', () {
      final addressUri = NavigationService.googleMapsDirectionsUri({
        'name': 'Example Bowls Club',
        'address_line1': '1 High Street',
        'town_city': 'London',
        'postcode': 'SW1A 1AA',
      });
      final nameUri = NavigationService.googleMapsDirectionsUri({
        'name': 'Example Bowls Club',
      });

      expect(
        addressUri!.queryParameters['destination'],
        '1 High Street, London, SW1A 1AA',
      );
      expect(nameUri!.queryParameters['destination'], 'Example Bowls Club');
    });

    test('rejects unusable or out-of-range coordinates', () {
      final uri = NavigationService.googleMapsDirectionsUri({
        'latitude': 95,
        'longitude': -0.1,
      });

      expect(uri, isNull);
    });
  });

  group('NavigationService.wazeDirectionsUri', () {
    test('uses coordinates before address or name', () {
      final uri = NavigationService.wazeDirectionsUri({
        'name': 'Example Bowls Club',
        'address_line1': '1 High Street',
        'latitude': 51.5007,
        'longitude': -0.1246,
      });

      expect(uri, isNotNull);
      expect(uri!.host, 'waze.com');
      expect(uri.queryParameters['ll'], '51.5007,-0.1246');
      expect(uri.queryParameters['navigate'], 'yes');
      expect(uri.queryParameters['q'], isNull);
    });

    test('falls back to address and then venue name', () {
      final addressUri = NavigationService.wazeDirectionsUri({
        'name': 'Example Bowls Club',
        'address_line1': '1 High Street',
        'town_city': 'London',
      });
      final nameUri = NavigationService.wazeDirectionsUri({
        'name': 'Example Bowls Club',
      });

      expect(addressUri!.queryParameters['q'], '1 High Street, London');
      expect(nameUri!.queryParameters['q'], 'Example Bowls Club');
    });
  });
}

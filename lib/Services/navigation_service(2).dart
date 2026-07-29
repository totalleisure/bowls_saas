import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared navigation entry point for every venue-aware screen.
///
/// The origin is deliberately omitted. Google Maps and Waze can therefore use
/// the device's current location when it is available. Destination selection
/// is consistent throughout the app:
///
/// 1. Google Place ID
/// 2. Latitude/longitude
/// 3. Postal address
/// 4. Venue name
class NavigationService {
  NavigationService._();

  static const String _wazeUtmSource = 'totalleisuresolutions_bowls';

  static String _text(dynamic value) => (value ?? '').toString().trim();

  static double? _coordinate(
    dynamic value, {
    required double minimum,
    required double maximum,
  }) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(_text(value));

    if (parsed == null || !parsed.isFinite) return null;
    if (parsed < minimum || parsed > maximum) return null;
    return parsed;
  }

  static ({double latitude, double longitude})? _coordinates(
    Map<String, dynamic> venue,
  ) {
    final latitude = _coordinate(
      venue['latitude'],
      minimum: -90,
      maximum: 90,
    );
    final longitude = _coordinate(
      venue['longitude'],
      minimum: -180,
      maximum: 180,
    );

    if (latitude == null || longitude == null) return null;
    return (latitude: latitude, longitude: longitude);
  }

  static String _address(Map<String, dynamic> venue) {
    return [
      _text(venue['address_line1']),
      _text(venue['address_line2']),
      _text(venue['town_city']),
      _text(venue['postcode']),
    ].where((part) => part.isNotEmpty).join(', ');
  }

  static String? _bestDestinationText(Map<String, dynamic> venue) {
    final coordinates = _coordinates(venue);
    if (coordinates != null) {
      return '${coordinates.latitude},${coordinates.longitude}';
    }

    final address = _address(venue);
    if (address.isNotEmpty) return address;

    final name = _text(venue['name']);
    return name.isEmpty ? null : name;
  }

  /// Builds the universal Google Maps directions URL.
  ///
  /// [dir_action=navigate] asks Google Maps to start turn-by-turn navigation
  /// when the current device location is available. On desktop it opens a
  /// route preview in the browser.
  static Uri? googleMapsDirectionsUri(Map<String, dynamic> venue) {
    final name = _text(venue['name']);
    final placeId = _text(venue['google_place_id']);
    final address = _address(venue);
    final coordinates = _coordinates(venue);

    final parameters = <String, String>{
      'api': '1',
      'travelmode': 'driving',
      'dir_action': 'navigate',
    };

    if (placeId.isNotEmpty) {
      // Google requires a human-readable destination whenever a Place ID is
      // supplied. The Place ID remains authoritative; the text is its fallback.
      final destination = name.isNotEmpty
          ? name
          : address.isNotEmpty
          ? address
          : coordinates != null
          ? '${coordinates.latitude},${coordinates.longitude}'
          : null;

      if (destination == null) return null;
      parameters['destination'] = destination;
      parameters['destination_place_id'] = placeId;
    } else {
      final destination = _bestDestinationText(venue);
      if (destination == null) return null;
      parameters['destination'] = destination;
    }

    return Uri.https('www.google.com', '/maps/dir/', parameters);
  }

  /// Builds a Waze universal deep link.
  ///
  /// Coordinates are preferred because Waze does not accept Google Place IDs.
  /// The universal https link opens the Waze app on supported mobile devices
  /// and falls back to Waze Live Map in a browser.
  static Uri? wazeDirectionsUri(Map<String, dynamic> venue) {
    final coordinates = _coordinates(venue);
    final address = _address(venue);
    final name = _text(venue['name']);

    if (coordinates != null) {
      return Uri.https('waze.com', '/ul', {
        'll': '${coordinates.latitude},${coordinates.longitude}',
        'navigate': 'yes',
        'utm_source': _wazeUtmSource,
      });
    }

    final query = address.isNotEmpty ? address : name;
    if (query.isEmpty) return null;

    return Uri.https('waze.com', '/ul', {
      'q': query,
      'navigate': 'yes',
      'utm_source': _wazeUtmSource,
    });
  }

  static bool canNavigate(Map<String, dynamic> venue) {
    return googleMapsDirectionsUri(venue) != null ||
        wazeDirectionsUri(venue) != null;
  }

  static bool get _isDesktopOrWeb {
    return kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  static Future<void> navigateToVenue({
    required BuildContext context,
    required Map<String, dynamic> venue,
  }) async {
    final googleUri = googleMapsDirectionsUri(venue);
    final wazeUri = wazeDirectionsUri(venue);

    if (googleUri == null && wazeUri == null) {
      _message(
        context,
        'No usable address or location is available for this venue.',
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text(
                'Choose navigation',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _text(venue['name']).isEmpty
                    ? 'Venue directions'
                    : _text(venue['name']),
              ),
            ),
            if (googleUri != null)
              ListTile(
                leading: const Icon(Icons.map_outlined),
                title: const Text('Google Maps'),
                subtitle: Text(
                  _isDesktopOrWeb
                      ? 'Open driving directions in Google Maps'
                      : 'Start driving directions from your current location',
                ),
                onTap: () => _selectProvider(
                  context: context,
                  sheetContext: sheetContext,
                  provider: _NavigationProvider.googleMaps,
                  uri: googleUri,
                ),
              ),
            if (wazeUri != null)
              ListTile(
                leading: const Icon(Icons.navigation_outlined),
                title: const Text('Waze'),
                subtitle: Text(
                  _isDesktopOrWeb
                      ? 'Open the route in Waze Live Map'
                      : 'Start Waze navigation from your current location',
                ),
                onTap: () => _selectProvider(
                  context: context,
                  sheetContext: sheetContext,
                  provider: _NavigationProvider.waze,
                  uri: wazeUri,
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static void _selectProvider({
    required BuildContext context,
    required BuildContext sheetContext,
    required _NavigationProvider provider,
    required Uri uri,
  }) {
    // Start the launch while still inside the user's tap callback. This matters
    // on web, where browsers can block new tabs not opened by a user action.
    final launch = _launchNavigation(
      context: context,
      provider: provider,
      uri: uri,
    );
    Navigator.of(sheetContext).pop();
    unawaited(launch);
  }

  static Future<void> _launchNavigation({
    required BuildContext context,
    required _NavigationProvider provider,
    required Uri uri,
  }) async {
    var opened = false;

    try {
      opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } catch (error, stackTrace) {
      debugPrint('External navigation launch failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    // A platform may reject the specifically requested launch mode. Retry with
    // its default handler before presenting an error to the member.
    if (!opened) {
      try {
        opened = await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: '_blank',
        );
      } catch (error, stackTrace) {
        debugPrint('Default navigation launch failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    if (!opened && context.mounted) {
      _message(
        context,
        provider == _NavigationProvider.googleMaps
            ? 'Unable to open Google Maps directions.'
            : 'Unable to open Waze directions.',
      );
    }
  }

  static void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

enum _NavigationProvider { googleMaps, waze }

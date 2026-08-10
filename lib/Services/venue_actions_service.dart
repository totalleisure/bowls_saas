import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'navigation_service.dart';

/// Shared actions for every venue-aware screen.
///
/// Navigation remains delegated to [NavigationService]. This service owns the
/// other common venue behaviours so the Dashboard, fixture details, diary and
/// venue maintenance screens all behave consistently.
class VenueActionsService {
  VenueActionsService._();

  static String text(dynamic value) => (value ?? '').toString().trim();

  static String address(Map<String, dynamic> venue) {
    return [
      text(venue['address_line1']),
      text(venue['address_line2']),
      text(venue['town_city']),
      text(venue['postcode']),
    ].where((part) => part.isNotEmpty).join(', ');
  }

  static String website(Map<String, dynamic> venue) =>
      text(venue['website_url']);

  static String googleMapsUrl(Map<String, dynamic> venue) {
    final googleUrl = text(venue['google_maps_url']);
    if (googleUrl.isNotEmpty) return googleUrl;
    return text(venue['directions_url']);
  }

  static String phone(Map<String, dynamic> venue) =>
      text(venue['contact_phone']);

  static String email(Map<String, dynamic> venue) =>
      text(venue['contact_email']);

  static bool hasWebsite(Map<String, dynamic> venue) =>
      _normaliseWebUri(website(venue)) != null;

  static bool hasGoogleMapsListing(Map<String, dynamic> venue) =>
      _normaliseWebUri(googleMapsUrl(venue)) != null;

  static bool hasPhone(Map<String, dynamic> venue) => phone(venue).isNotEmpty;

  static bool hasEmail(Map<String, dynamic> venue) => email(venue).isNotEmpty;

  static bool hasAddress(Map<String, dynamic> venue) => address(venue).isNotEmpty;

  static bool canNavigate(Map<String, dynamic> venue) =>
      NavigationService.canNavigate(venue);

  static bool hasShareableDetails(Map<String, dynamic> venue) {
    return text(venue['name']).isNotEmpty ||
        hasAddress(venue) ||
        hasPhone(venue) ||
        hasEmail(venue) ||
        hasWebsite(venue) ||
        hasGoogleMapsListing(venue);
  }

  static Future<void> openWebsite({
    required BuildContext context,
    required Map<String, dynamic> venue,
  }) async {
    final uri = _normaliseWebUri(website(venue));
    if (uri == null) {
      _message(context, 'No usable website has been recorded for this venue.');
      return;
    }

    await _launch(
      context: context,
      uri: uri,
      failureMessage: 'Unable to open the venue website.',
    );
  }

  static Future<void> openGoogleMapsListing({
    required BuildContext context,
    required Map<String, dynamic> venue,
  }) async {
    final uri = _normaliseWebUri(googleMapsUrl(venue));
    if (uri == null) {
      _message(
        context,
        'No Google Maps listing has been recorded for this venue.',
      );
      return;
    }

    await _launch(
      context: context,
      uri: uri,
      failureMessage: 'Unable to open the Google Maps listing.',
    );
  }

  static Future<void> navigate({
    required BuildContext context,
    required Map<String, dynamic> venue,
  }) {
    return NavigationService.navigateToVenue(
      context: context,
      venue: venue,
    );
  }

  static Future<void> call({
    required BuildContext context,
    required Map<String, dynamic> venue,
  }) async {
    final number = phone(venue);
    if (number.isEmpty) {
      _message(context, 'No telephone number has been recorded for this venue.');
      return;
    }

    await _launch(
      context: context,
      uri: Uri(scheme: 'tel', path: number),
      failureMessage: 'Unable to open the telephone app.',
    );
  }

  static Future<void> sendEmail({
    required BuildContext context,
    required Map<String, dynamic> venue,
  }) async {
    final address = email(venue);
    if (address.isEmpty) {
      _message(context, 'No email address has been recorded for this venue.');
      return;
    }

    final venueName = text(venue['name']);
    final uri = Uri(
      scheme: 'mailto',
      path: address,
      queryParameters: venueName.isEmpty
          ? null
          : {'subject': 'Enquiry about $venueName'},
    );

    await _launch(
      context: context,
      uri: uri,
      failureMessage: 'Unable to open the email app.',
    );
  }

  static Future<void> copyAddress({
    required BuildContext context,
    required Map<String, dynamic> venue,
  }) async {
    final value = address(venue);
    if (value.isEmpty) {
      _message(context, 'No address has been recorded for this venue.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      _message(context, 'Venue address copied.');
    }
  }

  static Future<void> shareVenue({
    required BuildContext context,
    required Map<String, dynamic> venue,
  }) async {
    final shareText = buildShareText(venue);
    if (shareText.isEmpty) {
      _message(context, 'There are no venue details to share.');
      return;
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: shareText,
          subject: text(venue['name']).isEmpty
              ? 'Venue details'
              : text(venue['name']),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Venue share failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (context.mounted) {
        _message(context, 'Unable to share the venue details.');
      }
    }
  }

  static String buildShareText(Map<String, dynamic> venue) {
    final lines = <String>[];

    final name = text(venue['name']);
    final postalAddress = address(venue);
    final telephone = phone(venue);
    final emailAddress = email(venue);
    final websiteUrl = website(venue);
    final mapsUrl = googleMapsUrl(venue);

    if (name.isNotEmpty) lines.add(name);
    if (postalAddress.isNotEmpty) lines.add(postalAddress);
    if (telephone.isNotEmpty) lines.add('Telephone: $telephone');
    if (emailAddress.isNotEmpty) lines.add('Email: $emailAddress');
    if (websiteUrl.isNotEmpty) lines.add('Website: $websiteUrl');
    if (mapsUrl.isNotEmpty) lines.add('Google Maps: $mapsUrl');

    return lines.join('\n');
  }

  static Uri? _normaliseWebUri(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }

  static Future<void> _launch({
    required BuildContext context,
    required Uri uri,
    required String failureMessage,
  }) async {
    var opened = false;

    try {
      opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } catch (error, stackTrace) {
      debugPrint('Venue action launch failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    if (!opened) {
      try {
        opened = await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: '_blank',
        );
      } catch (error, stackTrace) {
        debugPrint('Venue action default launch failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    if (!opened && context.mounted) {
      _message(context, failureMessage);
    }
  }

  static void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

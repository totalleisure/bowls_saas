import 'dart:io';

import 'package:bowls_saas/services/fixture_communications_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses separate versioned attachment update counts', () {
    final result = TeamSheetAttachmentResult.fromRpc({
      'composition_version': 7,
      'notification_rows_updated': 4,
      'email_rows_updated': 2,
    });

    expect(result.compositionVersion, 7);
    expect(result.notificationRowsUpdated, 4);
    expect(result.emailRowsUpdated, 2);
  });

  test('rejects an invalid attachment RPC response', () {
    expect(
      () => TeamSheetAttachmentResult.fromRpc(3),
      throwsA(isA<FormatException>()),
    );
  });

  test('enforces the decoded 2 MB PDF ceiling before Base64 encoding', () {
    final source = File(
      'lib/Services/fixture_communications_service.dart',
    ).readAsStringSync();

    expect(source, contains('pdfBytes.length > 2000000'));
    expect(source, contains('base64Encode(pdfBytes)'));
  });
}

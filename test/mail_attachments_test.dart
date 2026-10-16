import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/communications/mail_attachments.dart';
import 'package:bowls_saas/features/communications/mailing_list_message_screen.dart';

class Picker extends FilePicker {
  List<PlatformFile>? files;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    expect(allowMultiple, isTrue);
    expect(withReadStream, isTrue);
    return files == null ? null : FilePickerResult(files!);
  }
}

PlatformFile file(String name, String text) => PlatformFile(
  name: name,
  size: text.length,
  bytes: Uint8List.fromList(utf8.encode(text)),
);

void main() {
  final picker = Picker();
  final queued = <Map<String, dynamic>>[];
  var fail = false;
  setUpAll(() async {
    FilePicker.platform = picker;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((req) async {
        dynamic data;
        if (req.url.path.endsWith('/mailing_lists')) {
          data = {
            'id': 'list',
            'club_id': 'club',
            'name': 'Newsletter',
            'is_active': true,
          };
        } else if (req.url.path.endsWith('/mailing_list_members')) {
          data = [
            {
              'member_profile_id': 'member',
              'member_profile': {'email_address': 'test@example.invalid'},
            },
          ];
        } else if (req.url.path.endsWith('/club_memberships')) {
          data = [
            {'member_profile_id': 'member'},
          ];
        } else if (req.url.path.endsWith(
          '/queue_mailing_list_message_with_attachments',
        )) {
          queued.add(Map<String, dynamic>.from(jsonDecode(req.body)));
          if (fail) {
            return http.Response(
              '{"message":"Queue unavailable"}',
              500,
              request: req,
              headers: {'content-type': 'application/json'},
            );
          }
          data = {
            'recipient_count': 1,
            'app_messages_created': 1,
            'emails_queued': 1,
          };
        } else {
          throw StateError(req.url.toString());
        }
        return http.Response(
          jsonEncode(data),
          200,
          request: req,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    queued.clear();
    fail = false;
    picker.files = [file('Guide.pdf', 'pdf'), file('Times.csv', 'csv')];
  });

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      const MaterialApp(
        home: MailingListMessageScreen(
          clubId: 'club',
          mailingListId: 'list',
          mailingListName: 'Newsletter',
        ),
      ),
    );
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(0), 'Update');
    await t.enterText(find.byType(TextField).at(1), 'Please see attached.');
  }

  Future<void> tap(WidgetTester t, String text) async {
    await t.ensureVisible(find.text(text));
    await t.tap(find.text(text));
    if (text == 'Review and Send' || text == 'Send') {
      await t.pump(const Duration(milliseconds: 400));
    } else {
      await t.pumpAndSettle();
    }
  }

  testWidgets(
    'multiple local files appear in review and exact bytes reach RPC',
    (t) async {
      await open(t);
      await tap(t, 'Add attachments');
      expect(find.text('Guide.pdf'), findsOneWidget);
      expect(find.text('Times.csv'), findsOneWidget);
      await tap(t, 'Review and Send');
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Guide.pdf'),
        ),
        findsOneWidget,
      );
      expect(queued, isEmpty);
      await tap(t, 'Send');
      expect(queued, hasLength(1));
      final attachments = queued.single['p_attachments'] as List;
      expect(attachments.map((a) => a['name']), ['Guide.pdf', 'Times.csv']);
      expect(utf8.decode(base64Decode(attachments[1]['contentBytes'])), 'csv');
      expect(find.text('Emails queued: 1'), findsOneWidget);
    },
  );
  testWidgets('remove and cancelled file picker preserve the remaining list', (
    t,
  ) async {
    await open(t);
    await tap(t, 'Add attachments');
    await t.tap(find.byTooltip('Remove Guide.pdf'));
    await t.pumpAndSettle();
    picker.files = null;
    await tap(t, 'Add attachments');
    expect(find.text('Guide.pdf'), findsNothing);
    expect(find.text('Times.csv'), findsOneWidget);
    await tap(t, 'Review and Send');
    await tap(t, 'Cancel');
    expect(queued, isEmpty);
    await tap(t, 'Review and Send');
    await tap(t, 'Send');
    expect(
      (queued.single['p_attachments'] as List).single['name'],
      'Times.csv',
    );
  });
  testWidgets(
    'app-only cannot silently discard attachments; failed send retains them',
    (t) async {
      await open(t);
      await tap(t, 'Add attachments');
      await tap(t, 'Send email');
      await tap(t, 'Review and Send');
      expect(queued, isEmpty);
      expect(
        find.text('Enable email or remove the attachments before sending.'),
        findsOneWidget,
      );
      await tap(t, 'Send email');
      fail = true;
      await tap(t, 'Review and Send');
      await tap(t, 'Send');
      expect(find.text('Guide.pdf'), findsOneWidget);
      expect(find.text('Review and Send'), findsOneWidget);
    },
  );
  testWidgets('messages without attachments still work', (t) async {
    await open(t);
    await tap(t, 'Review and Send');
    await tap(t, 'Send');
    expect(queued.single['p_attachments'], isEmpty);
  });
  test(
    'read streams and enforce actual bytes, duplicates, empty and aggregate limits',
    () async {
      final result = await readMailAttachments([
        PlatformFile(
          name: 'a.pdf',
          size: 3,
          readStream: Stream.fromIterable([
            [1],
            [2, 3],
          ]),
        ),
      ], []);
      expect(result.single.bytes, [1, 2, 3]);
      await expectLater(
        readMailAttachments([file('A.PDF', 'x')], result),
        throwsFormatException,
      );
      await expectLater(
        readMailAttachments([file('empty', '')], []),
        throwsFormatException,
      );
      await expectLater(
        readMailAttachments([
          PlatformFile(
            name: 'huge',
            size: 1,
            readStream: Stream.value(Uint8List(maxMailAttachmentBytes + 1)),
          ),
        ], []),
        throwsFormatException,
      );
      await expectLater(
        readMailAttachments(
          [file('extra', 'x')],
          [MailAttachment('full', Uint8List(maxMailAttachmentBytes))],
        ),
        throwsFormatException,
      );
      await expectLater(
        readMailAttachments(List.generate(11, (i) => file('$i', 'x')), []),
        throwsFormatException,
      );
    },
  );
}

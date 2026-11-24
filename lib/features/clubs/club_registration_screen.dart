import 'club_online_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../secrets.dart';
import 'staging_club_onboarding_screen.dart';
import 'my_clubs_screen.dart';

bool get stagingClubRegistrationEnabled => const {
  'egxdkaotepgfjmszxlyn.supabase.co',
  'xfjelvvfoguzukgvxchh.supabase.co',
}.contains(Uri.parse(Secrets.supabaseUrl).host);

class ClubSetupEntry extends StatelessWidget {
  const ClubSetupEntry({super.key, this.welcome = false});
  final bool welcome;
  @override
  Widget build(BuildContext context) {
    if (!stagingClubRegistrationEnabled) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xff1e3a8a),
            backgroundColor: const Color(0xffdbeafe),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: Color(0xff1e3a8a), width: 1.5),
            ),
          ),
          icon: const Icon(Icons.add_home_outlined, size: 19),
          label: Text(
            'Set up your club',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ClubRegistrationScreen(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Public entry in STAGING only. All verification and creation gates are server-enforced.
class ClubRegistrationScreen extends StatefulWidget {
  const ClubRegistrationScreen({
    super.key,
    this.request,
    this.verifySignIn,
    this.setupBuilder,
  });
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? request;
  final Future<void> Function(String)? verifySignIn;
  final WidgetBuilder? setupBuilder;
  @override
  State<ClubRegistrationScreen> createState() => _ClubRegistrationScreenState();
}

class _ClubRegistrationScreenState extends State<ClubRegistrationScreen> {
  final query = TextEditingController(),
      first = TextEditingController(),
      last = TextEditingController(),
      email = TextEditingController(),
      phone = TextEditingController(),
      websiteAddress = TextEditingController(),
      code = TextEditingController();
  bool busy = false, authority = false, sent = false, contact = false;
  bool usingWebsite = false;
  String? error, requestId, duplicate;
  List<Map<String, dynamic>> places = [];
  Map<String, dynamic>? selected;
  @override
  void dispose() {
    for (final c in [query, first, last, email, phone, websiteAddress, code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> call(Map<String, dynamic> data) async {
    if (widget.request != null) return widget.request!(data);
    if (!stagingClubRegistrationEnabled) throw StateError('Staging only');
    try {
      final result = await Supabase.instance.client.functions.invoke(
        'staging-club-registration',
        body: data,
      );
      return Map<String, dynamic>.from(result.data as Map);
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] is String)
        return {'error': details['error']};
      rethrow;
    }
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted)
        setState(() {
          error =
              'We could not complete that check just now. Your details are still here. Please try again or contact Wayne.';
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> search() => findClub('search');
  Future<void> checkWebsite() => findClub('website');
  Future<void> findClub(String action) => run(() async {
    final r = await call({
      'action': action,
      'query': query.text.trim(),
      if (action == 'website') 'website_url': websiteAddress.text.trim(),
    });
    if (!mounted) return;
    setState(() {
      error = r['error'] as String?;
      if (error == null) {
        places = (r['places'] as List? ?? [])
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList();
        requestId = r['request_id'] as String?;
        selected = null;
        sent = false;
        duplicate = null;
      }
      contact = error != null || places.isEmpty;
    });
  });

  Future<void> send() => run(() async {
    final r = await call({
      'action': 'send',
      'request_id': requestId,
      'place_id': selected?['placeId'],
      'first_name': first.text.trim(),
      'last_name': last.text.trim(),
      'email': email.text.trim(),
      'phone': phone.text.trim(),
      'authority': authority,
    });
    if (!mounted) return;
    setState(() {
      error = r['error'] as String?;
      duplicate = r['duplicates'] is List
          ? (r['duplicates'] as List).join(', ')
          : null;
      contact = r['contact'] == true || duplicate != null;
      sent = r['sent'] == true;
      if (sent) {
        code.clear();
        selected = Map<String, dynamic>.from(r['place'] as Map);
      }
    });
  });

  Future<void> verify() => run(() async {
    final r = await call({
      'action': 'verify',
      'request_id': requestId,
      'code': code.text.trim(),
    });
    if (!mounted) return;
    if (r['verified'] != true || r['token_hash'] is! String) {
      setState(
        () => error =
            r['error'] as String? ?? 'Please check your code and try again.',
      );
      return;
    }
    if (widget.verifySignIn != null) {
      await widget.verifySignIn!(r['token_hash'] as String);
    } else {
      await Supabase.instance.client.auth.verifyOTP(
        tokenHash: r['token_hash'] as String,
        type: r['token_type'] == 'signup' ? OtpType.signup : OtpType.magiclink,
      );
    }
    // A changed sign-in identity replaces AuthGate's navigator. For the same
    // signed-in identity, explicitly enter setup instead.
    if (mounted)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder:
              widget.setupBuilder ?? (_) => const StagingClubOnboardingScreen(),
        ),
      );
  });

  Widget field(
    String label,
    TextEditingController c, {
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextField(
      controller: c,
      enabled: !busy && !sent,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ClubOnlineScaffold(
    appBar: AppBar(title: const Text('Set up your club')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Let’s bring your club online',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'For Secretaries and authorised club representatives. First, we’ll help you find your club and verify your email. Then we’ll guide you through setup, at your pace.',
                ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'You’re in control. No club is created until you review and finish setup. Member invitations are a separate step. Staging only sends email to approved test addresses.',
                    ),
                  ),
                ),
                if (!sent) ...[
                  field('Club name and town or postcode', query),
                  FilledButton.icon(
                    onPressed: busy ? null : search,
                    icon: const Icon(Icons.search),
                    label: const Text('Find my club'),
                  ),
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => setState(() => usingWebsite = !usingWebsite),
                    icon: const Icon(Icons.language),
                    label: const Text('Use my club’s website'),
                  ),
                  if (usingWebsite || contact) ...[
                    const Text(
                      'If Maps cannot find your club, enter its own website. We will check the club name and published contact address, then show you what we found.',
                    ),
                    field(
                      'Club website address',
                      websiteAddress,
                      keyboard: TextInputType.url,
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : checkWebsite,
                      child: const Text('Check club website'),
                    ),
                  ],
                  if (places.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text('Choose your club and check its address:'),
                    ),
                  for (final p in places)
                    Card(
                      child: ListTile(
                        title: Text('${p['name']}'),
                        subtitle: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${p['formattedAddress'] ?? ''}'),
                            if (p['source'] == 'website') ...[
                              const Text('Confirmed from the club’s website'),
                              SelectableText('${p['websiteUrl']}'),
                              TextButton(
                                onPressed: () async {
                                  final url = Uri.tryParse(
                                    '${p['evidenceUrl'] ?? p['websiteUrl']}',
                                  );
                                  if (url != null && url.scheme == 'https')
                                    await launchUrl(url);
                                },
                                child: const Text('View the published address'),
                              ),
                            ],
                          ],
                        ),
                        selected: selected?['placeId'] == p['placeId'],
                        trailing: selected?['placeId'] == p['placeId']
                            ? const Icon(Icons.check_circle)
                            : const Icon(Icons.chevron_right),
                        onTap: busy
                            ? null
                            : () => setState(() {
                                selected = p;
                                duplicate =
                                    p['duplicates'] is List &&
                                        (p['duplicates'] as List).isNotEmpty
                                    ? (p['duplicates'] as List).join(', ')
                                    : null;
                                contact = duplicate != null;
                                error = null;
                              }),
                      ),
                    ),
                  if (places.isNotEmpty)
                    Text(
                      places.any((p) => p['source'] == 'website')
                          ? 'Website details checked directly. Please review the club and address before continuing.'
                          : 'Club information from Google Maps',
                    ),
                  if (selected != null && !contact) ...[
                    const SizedBox(height: 20),
                    Text(
                      'A little about you',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    field('First name', first),
                    field('Surname', last),
                    field(
                      'Email address',
                      email,
                      keyboard: TextInputType.emailAddress,
                    ),
                    field(
                      'Telephone number',
                      phone,
                      keyboard: TextInputType.phone,
                    ),
                    const Text(
                      'We verify your email with a code. Your telephone number is for contact; it is not verified by text message.',
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: authority,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => authority = v ?? false),
                      title: const Text('I am authorised to set up this club'),
                    ),
                    FilledButton(
                      onPressed: busy ? null : send,
                      child: const Text('Send my verification code'),
                    ),
                  ],
                ] else ...[
                  const SizedBox(height: 16),
                  Text(
                    'Check your email',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'We’ve sent a six-digit code to ${email.text.trim()}. It expires in 10 minutes. Entering it also signs you in for club setup.',
                  ),
                  TextField(
                    controller: code,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Verification code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: busy ? null : verify,
                    child: const Text('Verify email and continue'),
                  ),
                  TextButton(
                    onPressed: busy ? null : send,
                    child: const Text('Send another code'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => setState(() => sent = false),
                    child: const Text('Change my email or club'),
                  ),
                ],
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator(),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      error!,
                      semanticsLabel: error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (contact) ClubRegistrationContact(duplicate: duplicate),
                if (!contact)
                  TextButton(
                    onPressed: () => setState(() => contact = true),
                    child: const Text('Need a hand? Contact Wayne'),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class ClubRegistrationContact extends StatelessWidget {
  const ClubRegistrationContact({super.key, this.duplicate});
  final String? duplicate;
  Future<void> open(BuildContext context, Uri uri) async {
    try {
      if (await launchUrl(uri)) return;
    } catch (_) {
      /* Contact details remain selectable. */
    }
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please use the contact details shown below.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Let’s help you get your club online',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            duplicate != null
                ? 'We found an existing club or home venue that may be yours: $duplicate. Contact Wayne so we can help you get the right access and avoid creating a duplicate.'
                : 'We couldn’t confidently confirm your club yet. Some clubs are listed under another name or share a venue. Contact Wayne and we’ll help you continue.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Your entered details are still here. No club has been created.',
          ),
          const SelectableText('+44 7710 325696\nwayne@totalleisure.com'),
          Wrap(
            spacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () =>
                    open(context, Uri(scheme: 'tel', path: '+447710325696')),
                icon: const Icon(Icons.call),
                label: const Text('Call Wayne'),
              ),
              OutlinedButton.icon(
                onPressed: () => open(
                  context,
                  Uri(
                    scheme: 'mailto',
                    path: 'wayne@totalleisure.com',
                    queryParameters: {
                      'subject': 'Help setting up my bowls club',
                    },
                  ),
                ),
                icon: const Icon(Icons.email_outlined),
                label: const Text('Email Wayne'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Restore a verified Secretary's setup after the sign-in replaces navigation.
class StagingRegistrationLanding extends StatefulWidget {
  const StagingRegistrationLanding({super.key});
  @override
  State<StagingRegistrationLanding> createState() =>
      _StagingRegistrationLandingState();
}

class _StagingRegistrationLandingState
    extends State<StagingRegistrationLanding> {
  late Future<dynamic> registration = Supabase.instance.client.rpc(
    'my_staging_club_registration',
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: registration,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return ClubOnlineScaffold(
          body: Center(
            child: TextButton(
              onPressed: () => setState(
                () => registration = Supabase.instance.client.rpc(
                  'my_staging_club_registration',
                ),
              ),
              child: const Text('Retry loading your club setup'),
            ),
          ),
        );
      if (snapshot.connectionState != ConnectionState.done)
        return const ClubOnlineScaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      return snapshot.data is Map
          ? const StagingClubOnboardingScreen()
          : const MyClubsScreen();
    },
  );
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _clubFieldKey = GlobalKey();
  final _firstNameFieldKey = GlobalKey();
  final _surnameFieldKey = GlobalKey();
  final _phoneFieldKey = GlobalKey();
  final _emailFieldKey = GlobalKey();
  final _confirmEmailFieldKey = GlobalKey();
  final _passwordFieldKey = GlobalKey();
  final _confirmPasswordFieldKey = GlobalKey();

  final _clubFocus = FocusNode();
  final _firstNameFocus = FocusNode();
  final _surnameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _confirmEmailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  final _firstName = TextEditingController();
  final _surname = TextEditingController();
  final _address1 = TextEditingController();
  final _address2 = TextEditingController();
  final _town = TextEditingController();
  final _county = TextEditingController();
  final _postcode = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _confirmEmail = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _loading = false;
  bool _clubsLoading = true;
  bool _hasUnsavedChanges = false;
  bool _validateOnChange = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  int _brandingSetNo = 0;

  String? _selectedClubId;
  String? _selectedClubName;
  String? _gender;

  List<Map<String, dynamic>> _clubs = [];

  String _blankBackgroundImageForWidth(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final shortestSide = size.shortestSide;

    const existingBrandingSets = {0, 2};
    final suffix = existingBrandingSets.contains(_brandingSetNo)
        ? _brandingSetNo
        : 0;

    if (width >= 1000) {
      return 'assets/images/blank_bg_desktop_$suffix.png';
    } else if (shortestSide >= 600) {
      return 'assets/images/blank_bg_tablet_$suffix.png';
    } else {
      return 'assets/images/blank_bg_phone_$suffix.png';
    }
  }

  Widget _requiredLabel(String text) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text),
          const TextSpan(
            text: ' *',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String? _requiredValidator(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  bool _looksLikeEmail(String value) {
    final email = value.trim();
    final at = email.indexOf('@');
    final dot = email.lastIndexOf('.');
    return at > 0 && dot > at + 1 && dot < email.length - 1;
  }

  void _markDirty() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRememberedBranding();
    _loadClubs();
  }

  @override
  void dispose() {
    _clubFocus.dispose();
    _firstNameFocus.dispose();
    _surnameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    _confirmEmailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();

    _firstName.dispose();
    _surname.dispose();
    _address1.dispose();
    _address2.dispose();
    _town.dispose();
    _county.dispose();
    _postcode.dispose();
    _phone.dispose();
    _email.dispose();
    _confirmEmail.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _loadRememberedBranding() async {
    final prefs = await SharedPreferences.getInstance();

    final remembered = prefs.getInt('last_branding_set_no') ?? 0;

    if (!mounted) return;

    setState(() {
      _brandingSetNo = remembered;
    });
  }

  Future<void> _loadClubs() async {
    try {
      debugPrint('Loading clubs...');
      final result = await Supabase.instance.client
          .from('clubs')
          .select('id, name, branding_set_no')
          .order('name');

      debugPrint('Loading clubs 2...');
      debugPrint('Clubs loaded: ${result.length}');
      debugPrint('Clubs result: $result');

      if (!mounted) return;

      setState(() {
        _clubs = List<Map<String, dynamic>>.from(result);
        _clubsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _clubsLoading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load clubs: $e')));
    }
  }

  String _friendlyRegistrationError(Object e) {
    final text = e.toString();

    final errorMatch = RegExp(
      r'error:\s*([^,})]+(?:[,.][^})]+)?)',
    ).firstMatch(text);

    if (errorMatch != null) {
      return errorMatch.group(1)!.trim();
    }

    if (text.contains('already registered')) {
      return 'You are already registered with this club. Please sign in, or use Forgotten Password if you need to reset access.';
    }

    return 'Registration could not be completed. Please check your details and try again.';
  }

  Future<void> _revealAndFocus(GlobalKey key, FocusNode focusNode) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    final fieldContext = key.currentContext;
    if (fieldContext != null) {
      await Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.20,
      );
    }

    if (mounted) {
      focusNode.requestFocus();
    }
  }

  Future<void> _focusFirstInvalidField() async {
    if (_selectedClubId == null) {
      await _revealAndFocus(_clubFieldKey, _clubFocus);
      return;
    }

    if (_firstName.text.trim().isEmpty) {
      await _revealAndFocus(_firstNameFieldKey, _firstNameFocus);
      return;
    }

    if (_surname.text.trim().isEmpty) {
      await _revealAndFocus(_surnameFieldKey, _surnameFocus);
      return;
    }

    if (_phone.text.trim().isEmpty) {
      await _revealAndFocus(_phoneFieldKey, _phoneFocus);
      return;
    }

    final email = _email.text.trim();
    if (email.isEmpty || !_looksLikeEmail(email)) {
      await _revealAndFocus(_emailFieldKey, _emailFocus);
      return;
    }

    final confirmEmail = _confirmEmail.text.trim();
    if (confirmEmail.isEmpty || confirmEmail != email) {
      await _revealAndFocus(_confirmEmailFieldKey, _confirmEmailFocus);
      return;
    }

    if (_password.text.isEmpty) {
      await _revealAndFocus(_passwordFieldKey, _passwordFocus);
      return;
    }

    if (_confirmPassword.text.isEmpty ||
        _confirmPassword.text != _password.text) {
      await _revealAndFocus(_confirmPasswordFieldKey, _confirmPasswordFocus);
    }
  }

  Future<void> _register() async {
    final formIsValid = _formKey.currentState?.validate() ?? false;

    if (!formIsValid) {
      if (!_validateOnChange) {
        setState(() {
          _validateOnChange = true;
        });
      }
      await _focusFirstInvalidField();
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'register_member',
        body: {
          'first_name': _firstName.text.trim(),
          'surname': _surname.text.trim(),
          'address_line1': _address1.text.trim(),
          'address_line2': _address2.text.trim(),
          'town_city': _town.text.trim(),
          'county': _county.text.trim(),
          'postcode': _postcode.text.trim(),
          'phone': _phone.text.trim(),
          'email': _email.text.trim(),
          'password': _password.text,
          'gender': _gender,
          'club_id': _selectedClubId,
        },
      );

      final data = response.data;

      if (response.status != 200 || data == null || data['success'] != true) {
        if (!mounted) return;

        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Registration'),
            content: Text(
              data?['error']?.toString() ??
                  'Registration could not be completed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        return;
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Welcome ${_firstName.text.trim()}'),
          content: Text(
            'Your request to join '
            '${data['club_name']} has been sent to the '
            'Membership Secretary for approval.\n\n'
            'In the meantime, please feel free to '
            'login and explore what’s happening '
            'at the club.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      setState(() {
        _hasUnsavedChanges = false;
      });

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Registration'),
          content: Text(_friendlyRegistrationError(e)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges || _loading,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _loading) return;

        final discard = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Discard registration?'),
            content: const Text(
              'You have entered registration details. Do you want to leave this screen and lose them?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );

        if (discard == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Register')),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          onPressed: _loading ? null : _register,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check),
          label: Text(_loading ? 'Registering...' : 'Register'),
        ),
        body: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(_blankBackgroundImageForWidth(context)),
              fit: BoxFit.cover,
            ),
          ),
          child: _clubsLoading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  autovalidateMode: _validateOnChange
                      ? AutovalidateMode.onUserInteraction
                      : AutovalidateMode.disabled,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.72),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 8),
                            const Text(
                              '* Required',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),

                            Container(
                              key: _clubFieldKey,
                              child: DropdownButtonFormField<String>(
                                focusNode: _clubFocus,
                                initialValue: _selectedClubId,
                                decoration: InputDecoration(
                                  label: _requiredLabel('Select your Club'),
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) => value == null
                                    ? 'Club is required'
                                    : null,
                                items: _clubs.map((club) {
                                  return DropdownMenuItem<String>(
                                    value: club['id'].toString(),
                                    child: Text(club['name'].toString()),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedClubId = value;

                                    if (value != null) {
                                      final selected = _clubs.firstWhere(
                                        (c) => c['id'].toString() == value,
                                      );
                                      _selectedClubName = selected['name']
                                          .toString();
                                    } else {
                                      _selectedClubName = null;
                                    }
                                  });

                                  _markDirty();
                                },
                              ),
                            ),

                            const SizedBox(height: 16),

                            Container(
                              key: _firstNameFieldKey,
                              child: TextFormField(
                                controller: _firstName,
                                focusNode: _firstNameFocus,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  label: _requiredLabel('First Name'),
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) =>
                                    _requiredValidator(value, 'First name'),
                                onChanged: (_) => _markDirty(),
                              ),
                            ),

                            const SizedBox(height: 8),

                            Container(
                              key: _surnameFieldKey,
                              child: TextFormField(
                                controller: _surname,
                                focusNode: _surnameFocus,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  label: _requiredLabel('Surname'),
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) =>
                                    _requiredValidator(value, 'Surname'),
                                onChanged: (_) => _markDirty(),
                              ),
                            ),

                            const SizedBox(height: 8),

                            TextField(
                              controller: _address1,
                              decoration: const InputDecoration(
                                labelText: 'Address Line 1',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => _markDirty(),
                            ),

                            const SizedBox(height: 8),

                            TextField(
                              controller: _address2,
                              decoration: const InputDecoration(
                                labelText: 'Address Line 2',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => _markDirty(),
                            ),

                            const SizedBox(height: 8),

                            TextField(
                              controller: _town,
                              decoration: const InputDecoration(
                                labelText: 'Town / City',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => _markDirty(),
                            ),

                            const SizedBox(height: 8),

                            TextField(
                              controller: _county,
                              decoration: const InputDecoration(
                                labelText: 'County',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => _markDirty(),
                            ),

                            const SizedBox(height: 8),

                            TextField(
                              controller: _postcode,
                              decoration: const InputDecoration(
                                labelText: 'Postcode',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => _markDirty(),
                            ),

                            const SizedBox(height: 8),

                            Container(
                              key: _phoneFieldKey,
                              child: TextFormField(
                                controller: _phone,
                                focusNode: _phoneFocus,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  label: _requiredLabel('Mobile phone'),
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) =>
                                    _requiredValidator(value, 'Mobile phone'),
                                onChanged: (_) => _markDirty(),
                              ),
                            ),

                            const SizedBox(height: 8),

                            DropdownButtonFormField<String>(
                              initialValue: _gender,
                              decoration: const InputDecoration(
                                labelText: 'Gender',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'male',
                                  child: Text('Male'),
                                ),
                                DropdownMenuItem(
                                  value: 'female',
                                  child: Text('Female'),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _gender = value;
                                });

                                _markDirty();
                              },
                            ),

                            const SizedBox(height: 8),

                            Container(
                              key: _emailFieldKey,
                              child: TextFormField(
                                controller: _email,
                                focusNode: _emailFocus,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                decoration: InputDecoration(
                                  label: _requiredLabel('Email Address'),
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  final email = value?.trim() ?? '';
                                  if (email.isEmpty) {
                                    return 'Email address is required';
                                  }
                                  if (!_looksLikeEmail(email)) {
                                    return 'Please enter a valid email address';
                                  }
                                  return null;
                                },
                                onChanged: (_) => _markDirty(),
                              ),
                            ),

                            const SizedBox(height: 8),

                            Container(
                              key: _confirmEmailFieldKey,
                              child: TextFormField(
                                controller: _confirmEmail,
                                focusNode: _confirmEmailFocus,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                decoration: InputDecoration(
                                  label: _requiredLabel(
                                    'Confirm Email Address',
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  final email = value?.trim() ?? '';
                                  if (email.isEmpty) {
                                    return 'Confirm email address is required';
                                  }
                                  if (email != _email.text.trim()) {
                                    return 'Email addresses do not match';
                                  }
                                  return null;
                                },
                                onChanged: (_) => _markDirty(),
                              ),
                            ),

                            const SizedBox(height: 8),

                            Container(
                              key: _passwordFieldKey,
                              child: TextFormField(
                                controller: _password,
                                focusNode: _passwordFocus,
                                obscureText: !_showPassword,
                                textInputAction: TextInputAction.next,
                                enableSuggestions: false,
                                autocorrect: false,
                                decoration: InputDecoration(
                                  label: _requiredLabel('Password'),
                                  border: const OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    tooltip: _showPassword
                                        ? 'Hide password'
                                        : 'Show password',
                                    icon: Icon(
                                      _showPassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _showPassword = !_showPassword;
                                      });
                                    },
                                  ),
                                ),
                                validator: (value) =>
                                    _requiredValidator(value, 'Password'),
                                onChanged: (_) => _markDirty(),
                              ),
                            ),

                            const SizedBox(height: 8),

                            Container(
                              key: _confirmPasswordFieldKey,
                              child: TextFormField(
                                controller: _confirmPassword,
                                focusNode: _confirmPasswordFocus,
                                obscureText: !_showConfirmPassword,
                                textInputAction: TextInputAction.done,
                                enableSuggestions: false,
                                autocorrect: false,
                                decoration: InputDecoration(
                                  label: _requiredLabel('Confirm Password'),
                                  border: const OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    tooltip: _showConfirmPassword
                                        ? 'Hide password'
                                        : 'Show password',
                                    icon: Icon(
                                      _showConfirmPassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _showConfirmPassword =
                                            !_showConfirmPassword;
                                      });
                                    },
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Confirm password is required';
                                  }
                                  if (value != _password.text) {
                                    return 'Passwords do not match';
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) {
                                  if (!_loading) {
                                    _register();
                                  }
                                },
                                onChanged: (_) => _markDirty(),
                              ),
                            ),

                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luckygo_admin/global.dart'; // must expose negara, negeri, bahasa
import 'package:luckygo_admin/LandingPage/home_page.dart';
import 'package:luckygo_admin/login_register/register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  // Prevent repeatedly auto-opening the region dialog
  bool _regionCheckedOnce = false;

  static const String _domain = '@admin.com'; // change if you truly want '@amdin.com'

  // Country → States map
  static const Map<String, List<String>> _statesByCountry = {
    'Malaysia': [
      'Johor','Kedah','Kelantan','Melaka','Negeri Sembilan','Pahang','Penang',
      'Perak','Perlis','Sabah','Sarawak','Selangor','Terengganu',
      'Kuala Lumpur','Labuan','Putrajaya',
    ],
    'Indonesia': [
      'Aceh','North Sumatra','West Sumatra','Riau','Riau Islands','Jambi','Bengkulu','South Sumatra',
      'Bangka Belitung Islands','Lampung','Banten','DKI Jakarta','West Java','Central Java','DI Yogyakarta',
      'East Java','Bali','West Nusa Tenggara','East Nusa Tenggara',
      'West Kalimantan','Central Kalimantan','South Kalimantan','East Kalimantan','North Kalimantan',
      'North Sulawesi','Gorontalo','Central Sulawesi','South Sulawesi','Southeast Sulawesi','West Sulawesi',
      'Maluku','North Maluku','West Papua','Southwest Papua','Central Papua','Highland Papua','South Papua','Papua',
    ],
    'Timor-Leste': [
      'Aileu','Ainaro','Baucau','Bobonaro','Covalima','Dili','Ermera','Lautem',
      'Liquica','Manatuto','Manufahi','Oecusse','Viqueque',
    ],
  };

  // Country → Languages map (spellings as requested)
  static const Map<String, List<String>> _languagesByCountry = {
    'Malaysia': ['Malay', 'English', 'Chinese'],
    'Indonesia': ['Indon', 'English', 'Jawa', 'Chinese'],
    'Timor-Leste': ['Tetun', 'Portugese', 'English'],
  };

  @override
  void initState() {
    super.initState();
    _loadRegionPrefs();
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadRegionPrefs() async {
    final p = await SharedPreferences.getInstance();
    final c = p.getString('negara') ?? '';
    final s = p.getString('negeri') ?? '';
    final l = p.getString('bahasa') ?? '';

    if (c.isNotEmpty) negara = c;
    if (s.isNotEmpty) negeri = s;
    if (l.isNotEmpty) bahasa = l;

    if (mounted) {
      setState(() {});
      _maybePromptRegion(); // auto-open dialog if missing
    }
  }

  void _maybePromptRegion() {
    if (_regionCheckedOnce) return;
    _regionCheckedOnce = true;

    final missing = negara.isEmpty || negeri.isEmpty || bahasa.isEmpty;
    if (missing) {
      // Open after first frame to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureRegionAndLanguage();
      });
    }
  }

  String _emailFromPhone(String rawPhone) {
    final digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    return '$digits$_domain'; // e.g. 60123456789@admin.com
  }

  Future<bool> _ensureRegionAndLanguage() async {
    bool isMissing(String? v) => v == null || v.trim().isEmpty;

    if (!isMissing(negara) && !isMissing(negeri) && !isMissing(bahasa)) {
      return true; // already set
    }

    String? selCountry = isMissing(negara) ? null : negara;
    String? selState   = isMissing(negeri) ? null : negeri;
    String? selLang    = isMissing(bahasa) ? null : bahasa;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            final states = selCountry == null ? <String>[] : (_statesByCountry[selCountry] ?? <String>[]);
            final langs  = selCountry == null ? <String>[] : (_languagesByCountry[selCountry] ?? <String>[]);

            return AlertDialog(
              title: const Text("Sorry, we can't find where you registered"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "If you are a new user, tap Register below.\n"
                      "If you reinstalled this app, please complete the quick setup.",
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // Country
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Country',
                        border: OutlineInputBorder(),
                      ),
                      items: _statesByCountry.keys
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      value: selCountry,
                      onChanged: (v) {
                        setStateDialog(() {
                          selCountry = v;
                          selState = null;
                          selLang = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),

                    // State
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'State / Province',
                        border: OutlineInputBorder(),
                      ),
                      items: states.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      value: selState,
                      onChanged: (v) => setStateDialog(() => selState = v),
                    ),
                    const SizedBox(height: 12),

                    // Language (enabled after state)
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Language',
                        border: OutlineInputBorder(),
                      ),
                      items: langs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                      value: selLang,
                      onChanged: selState == null ? null : (v) => setStateDialog(() => selLang = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop(); // close dialog
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterPage()),
                    );
                  },
                  child: const Text('Register'),
                ),
                ElevatedButton(
                  onPressed: (selCountry != null && selState != null && selLang != null)
                      ? () async {
                          negara = selCountry!;
                          negeri = selState!;
                          bahasa = selLang!;

                          final p = await SharedPreferences.getInstance();
                          await p.setString('negara', negara);
                          await p.setString('negeri', negeri);
                          await p.setString('bahasa', bahasa);

                          if (context.mounted) Navigator.of(ctx).pop(true);
                        }
                      : null,
                  child: const Text('Save & Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    return ok == true;
  }

Future<void> _signIn() async {
  if (_busy) return;
  if (!(_formKey.currentState?.validate() ?? false)) return;
  FocusScope.of(context).unfocus();

  // Ensure region + language first
  final ready = await _ensureRegionAndLanguage();
  if (!ready) return;

  setState(() => _busy = true);

  try {
    final phoneDigits = _phone.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final email = '$phoneDigits$_domain';

    // 1) Auth sign-in
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: _password.text,
    );

    // 2) Verify admin profile exists in Firestore
    final docRef = FirebaseFirestore.instance
        .collection(negara)
        .doc(negeri)
        .collection('admin_account')
        .doc(phoneDigits);

    final snap = await docRef.get();
    final fullName = (snap.data()?['name'] as String?)?.trim() ?? '';

    if (!snap.exists || fullName.isEmpty) {
      // Invalid login for this region → sign out and show dialog
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text("Opps! sorry invalid login!"),
          content: const Text(
            "We can't find your admin registration for this phone in the selected Country/State.\n\n"
            "If you are a new user, please register.\n"
            "If you reinstalled the app, complete the quick setup.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );

      // stay on LoginPage
      _password.clear();
      setState(() => _busy = false);
      return;
    }

    // 3) Success → go Home
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  } on FirebaseAuthException catch (e) {
    final msg = e.message ?? 'Login failed';
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  } catch (_) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unexpected error')),
      );
    }
  } finally {
    if (mounted) setState(() => _busy = false);
  }
}

  @override
  Widget build(BuildContext context) {
    final hasRegion = negara.isNotEmpty && negeri.isNotEmpty && bahasa.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('LuckyGo Admin • Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // BIG BLUE REGION LINE (shown only when region is known)
                    if (hasRegion) ...[
                      Text(
                        '$bahasa • $negeri • $negara',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else
                      // If not set, auto-dialog already opens; show a hint here, too
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextButton.icon(
                          onPressed: _busy ? null : () => _ensureRegionAndLanguage(),
                          icon: const Icon(Icons.public),
                          label: const Text('Set Country • State • Language'),
                        ),
                      ),

                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        hintText: 'e.g. 60123456789',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final s = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                        if (s.isEmpty) return 'Enter phone';
                        if (s.length < 6) return 'Too short';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      onFieldSubmitted: (_) => _signIn(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Enter password' : null,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _signIn,
                        child: _busy
                            ? const SizedBox(
                                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Login'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Not yet a member? "),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const RegisterPage()),
                                  );
                                },
                          child: const Text("Register here"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Manual region change at any time
                    TextButton.icon(
                      onPressed: _busy ? null : () async => _ensureRegionAndLanguage(),
                      icon: const Icon(Icons.public),
                      label: Text(
                        hasRegion
                            ? 'Change: $negara • $negeri • $bahasa'
                            : 'Set Country • State • Language',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

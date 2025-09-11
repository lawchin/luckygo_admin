import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';        // ← add this
import 'package:luckygo_admin/global.dart';                        // ← add this (negara/negeri/bahasa)
import 'package:luckygo_admin/LandingPage/home_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  // Inputs
  String? _country;
  String? _state;
  String? _language;

  final _name = TextEditingController();
  final _idNo = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  bool _obscure2 = true;

  // Country → State/Province map
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

  // Country → Language options
  static const Map<String, List<String>> _languagesByCountry = {
    'Malaysia': ['Malay', 'English', 'Chinese'],
    'Indonesia': ['Indon', 'English', 'Jawa', 'Chinese'],
    'Timor-Leste': ['Tetun', 'Portugese', 'English'],
  };

  @override
  void dispose() {
    _name.dispose();
    _idNo.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String _emailFromPhone(String rawPhone) {
    final digitsOnly = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    return '$digitsOnly@admin.com';
  }

  Future<void> _register() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final country = _country;
    final state = _state;
    final lang = _language;

    if (country == null || state == null || lang == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select country, state, and language')),
      );
      return;
    }

    final phoneDigits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    final email = _emailFromPhone(_phone.text.trim());
    final pwd = _password.text;
    final name = _name.text.trim();
    final idNo = _idNo.text.trim();

    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    try {
      // 1) Auth registration
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pwd,
      );

      // 2) Firestore profile write
      final fs = FirebaseFirestore.instance;
      await fs
          .collection(country)
          .doc(state)
          .collection('admin_account')
          .doc(phoneDigits)
          .set({
        'name': name,
        'indentification': idNo, // kept as requested
        'phone': phoneDigits,
        'language': lang,
        'created_at': FieldValue.serverTimestamp(),
      });

      // 3) Save to globals + local storage (SharedPreferences)  ← NEW
      negara = country;
      negeri = state;
      bahasa = lang;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('negara', negara);
      await prefs.setString('negeri', negeri);
      await prefs.setString('bahasa', bahasa);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      final msg = e.message ?? 'Registration failed';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unexpected error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final states = _country == null ? <String>[] : (_statesByCountry[_country] ?? <String>[]);
    final langs = _country == null ? <String>[] : (_languagesByCountry[_country] ?? <String>[]);

    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                          value: _country,
                          onChanged: (v) {
                            setState(() {
                              _country = v;
                              _state = null;     // reset when country changes
                              _language = null;  // reset language too
                            });
                          },
                          validator: (v) => v == null ? 'Select country' : null,
                        ),
                        const SizedBox(height: 12),

                        // State
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'State / Province',
                            border: OutlineInputBorder(),
                          ),
                          items: states
                              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          value: _state,
                          onChanged: (v) => setState(() {
                            _state = v;
                            _language = null; // reset language on state change
                          }),
                          validator: (v) => v == null ? 'Select state' : null,
                        ),
                        const SizedBox(height: 12),

                        // Language (always visible; disabled until state chosen)
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Language',
                            border: OutlineInputBorder(),
                          ),
                          items: langs
                              .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                              .toList(),
                          value: _language,
                          onChanged: _state == null
                              ? null
                              : (v) => setState(() => _language = v),
                          validator: (v) {
                            if (_state == null) return 'Select state first';
                            return (v == null || v.isEmpty) ? 'Select language' : null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Full name
                        TextFormField(
                          controller: _name,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Enter full name' : null,
                        ),
                        const SizedBox(height: 12),

                        // ID number
                        TextFormField(
                          controller: _idNo,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'ID number',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Enter ID number' : null,
                        ),
                        const SizedBox(height: 12),

                        // Phone
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Phone (digits only)',
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

                        // Password
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.length < 6) ? 'Min 6 characters' : null,
                        ),
                        const SizedBox(height: 12),

                        // Confirm Password
                        TextFormField(
                          controller: _confirmPassword,
                          obscureText: _obscure2,
                          decoration: InputDecoration(
                            labelText: 'Confirm password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure2 ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscure2 = !_obscure2),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Re-enter password';
                            if (v != _password.text) return 'Passwords do not match';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _busy ? null : _register,
                            child: _busy
                                ? const SizedBox(
                                    width: 22, height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Submit'),
                          ),
                        ),
                        const SizedBox(height: 8),

                        TextButton(
                          onPressed: _busy ? null : () => Navigator.of(context).pop(),
                          child: const Text('Already have an account? Login'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

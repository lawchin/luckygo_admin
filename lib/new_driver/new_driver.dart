// new_driver.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:luckygo_admin/global.dart';
import 'driver_registration_details.dart';

class NewDriver extends StatelessWidget {
  const NewDriver({super.key});

  @override
  Widget build(BuildContext context) {
    final n = negara;
    final s = negeri;

    return Scaffold(
      appBar: AppBar(title: const Text('New Drivers (Pending Approval)')),
      body: (n == null || s == null || n.isEmpty || s.isEmpty)
          ? const Center(child: Text('Missing negara/negeri.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(n)
                  .doc(s)
                  .collection('driver_account')
                  .where('registration_approved', isEqualTo: false)
                  .where('form2_completed', isEqualTo: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }

                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No pending drivers found.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data();

                    final fullname = (data['fullname'] ?? '').toString();
                    final emailRaw = (data['email'] ?? '').toString();
                    final phoneFromEmail = _toPhoneFromEmail(emailRaw);
                    final registerDate =
                        _formatDateAny(data['register_date'] ?? data['created_at']);

                    return Card(
                      elevation: 2,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DriverRegistrationDetails(
                                driverId: doc.id,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _kv('Register Date', registerDate),
                              const SizedBox(height: 8),
                              _kv('Fullname', fullname.isEmpty ? '-' : fullname),
                              const SizedBox(height: 8),
                              _kv('Phone (from email)',
                                  phoneFromEmail.isEmpty ? '-' : phoneFromEmail),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  static String _toPhoneFromEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceFirst(RegExp(r'@driver\.com$', caseSensitive: false), '');
  }

  static String _formatDateAny(dynamic v) {
    if (v == null) return '-';
    if (v is Timestamp) return _formatYMDHMS(v.toDate());
    if (v is DateTime) return _formatYMDHMS(v);

    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return '-';
      final dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
      if (dateOnly.hasMatch(s)) return s;
      final parsed = DateTime.tryParse(s);
      if (parsed != null) return _formatYMDHMS(parsed);

      final re = RegExp(r'^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})');
      final m = re.firstMatch(s);
      if (m != null) return '${m.group(1)} ${m.group(2)}';
      return s;
    }

    return v.toString();
  }

  static String _formatYMDHMS(DateTime dt) {
    dt = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final y = dt.year.toString().padLeft(4, '0');
    final mo = two(dt.month);
    final d = two(dt.day);
    final h = two(dt.hour);
    final mi = two(dt.minute);
    final s = two(dt.second);
    return '$y-$mo-$d $h:$mi:$s';
  }

  static Widget _kv(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Expanded(child: SelectableText(value)),
      ],
    );
  }
}

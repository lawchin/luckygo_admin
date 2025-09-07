import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:luckygo_admin/global.dart'; // expects: String negara, negeri

class CustomerService extends StatelessWidget {
  const CustomerService({super.key});

  // ----- Firestore helpers -----
  CollectionReference<Map<String, dynamic>> _serviceDataCol() {
    return FirebaseFirestore.instance
        .collection(negara)
        .doc(negeri)
        .collection('help_center')
        .doc('customer_service')
        .collection('service_data');
  }

  Stream<int> _unseenCountStream() {
    return _serviceDataCol()
        .where('admin_seen', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customer Service')),
      body: StreamBuilder<int>(
        stream: _unseenCountStream(),
        builder: (context, countSnap) {
          if (countSnap.hasError) {
            return Center(child: Text('Error: ${countSnap.error}'));
          }
          if (!countSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final unseenCount = countSnap.data ?? 0;
          final showAll = unseenCount == 0;

          Query<Map<String, dynamic>> q = _serviceDataCol();
          if (!showAll) q = q.where('admin_seen', isEqualTo: false);

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: showAll
                    ? Colors.blue.withOpacity(.08)
                    : Colors.orange.withOpacity(.10),
                child: Text(
                  showAll
                      ? 'No unseen messages • Showing ALL messages'
                      : 'Showing $unseenCount unseen message(s)',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: q.snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('Error: ${snap.error}'));
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snap.data!.docs.toList()
                      ..sort((a, b) {
                        final da = _toDate(a.data()['timestamp']);
                        final db = _toDate(b.data()['timestamp']);
                        return db.compareTo(da); // newest first
                      });

                    if (docs.isEmpty) {
                      return const Center(child: Text('No messages yet.'));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final d = doc.data();

                        final refCode   = (d['refference'] as String?)?.trim() ?? '';
                        final message   = (d['message']   as String?)?.trim() ?? '';
                        final sender    = (d['sender']    as String?)?.trim() ?? ''; // 'driver' | 'passenger'
                        final userPhone = (d['user']      as String?)?.trim() ?? ''; // phone number
                        final name      = (d['name']      as String?)?.trim() ?? '';
                        final adminSeen = (d['admin_seen'] as bool?) ?? false;

                        final adminRemark = (d['admin_remark'] as String?) ??
                                            (d['admin_remak']  as String?) ??
                                            '';

                        final ts = _toDateOrNull(d['timestamp']);
                        final adminSeenTs = _toDateOrNull(d['admin_seen_timestamp']);

                        final greetName = name.isNotEmpty
                            ? name
                            : (userPhone.isNotEmpty ? userPhone : 'there');

                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showAdminResponseDialog(
                            pageContext: context,
                            docRef: doc.reference,
                            refCode: refCode,
                            greetName: greetName,
                            penghantar: sender,                 // will become '<sender>_account'
                            senderPhoneNumber: userPhone,       // doc id under that account
                            initialText: adminRemark,
                          ),
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.support_agent),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name.isEmpty ? '(no name)' : name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              refCode.isEmpty ? '(no ref)' : refCode,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: adminSeen
                                              ? Colors.green.withOpacity(.12)
                                              : Colors.orange.withOpacity(.12),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          adminSeen ? 'Seen' : 'Unseen',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  _kv('Message', message),
                                  _kv('Sender', sender),
                                  _kv('User', userPhone),
                                  _kv('Timestamp', ts?.toString() ?? '—'),
                                  if (adminRemark.trim().isNotEmpty)
                                    _kv('Admin remark', adminRemark.trim()),
                                  if (adminSeenTs != null)
                                    _kv('Seen at', adminSeenTs.toString()),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Tap card to reply',
                                    style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ----- Dialog: Admin Response -----
  Future<void> _showAdminResponseDialog({
    required BuildContext pageContext,
    required DocumentReference<Map<String, dynamic>> docRef,
    required String refCode,
    required String greetName,
    required String penghantar,          // 'driver' or 'passenger'
    required String senderPhoneNumber,   // phone number
    String? initialText,
  }) async {
    final controller = TextEditingController(text: initialText ?? '');

    await showDialog(
      context: pageContext,
      barrierDismissible: true,
      builder: (dialogCtx) {
        bool submitting = false;

        return StatefulBuilder(
          builder: (ctx, setState) {
            Future<void> submit() async {
              final typed = controller.text.trim();
              if (typed.isEmpty) {
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  const SnackBar(content: Text('Please type a response.')),
                );
                return;
              }
              if (penghantar.isEmpty || senderPhoneNumber.isEmpty) {
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  const SnackBar(content: Text('Missing sender info (account/phone).')),
                );
                return;
              }

              setState(() => submitting = true);

              // Always prefix:
              final finalReply =
                  'Hello $greetName,\nregarding your ref: $refCode, $typed.\n\nThank you,\nAdmin';

              try {
                // 1) Update the service_data doc with the full reply
                await docRef.update({
                  'admin_remark': finalReply,              // mirror for typo safety
                  'admin_seen': true,
                  'admin_seen_timestamp': FieldValue.serverTimestamp(),
                });

                // 2) Push a notification to <sender>_account/{phone}/notification_page
                final accountCollection = '${penghantar}_account'; // 'driver_account' or 'passenger_account'
                await FirebaseFirestore.instance
                    .collection(negara)
                    .doc(negeri)
                    .collection(accountCollection)
                    .doc(senderPhoneNumber)
                    .collection('notification_page')
                    .add({
                  'notification_description': finalReply,
                  'notification_date': FieldValue.serverTimestamp(),
                  'notification_seen': false,
                });

                if (pageContext.mounted) {
                  Navigator.of(dialogCtx).pop();
                  ScaffoldMessenger.of(pageContext).showSnackBar(
                    SnackBar(content: Text('Reply sent for ref: $refCode')),
                  );
                }
              } catch (e) {
                setState(() => submitting = false);
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  SnackBar(content: Text('Failed to submit: $e')),
                );
              }
            }

            return AlertDialog(
              title: const Text('Admin Response'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Greeting auto-added:\n'
                        'Hello $greetName,\n'
                        'regarding your ref: $refCode, …\n\n'
                        'Thank you,\nAdmin',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: 'Type your message… (we prepend the greeting above)',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: submitting ? null : () => controller.clear(),
                  child: const Text('Clear'),
                ),
                ElevatedButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ----- Small UI helpers -----
Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(v)),
        ],
      ),
    );

// Timestamp parsing helpers
DateTime _toDate(dynamic t) =>
    (t is Timestamp) ? t.toDate() : DateTime.fromMillisecondsSinceEpoch(0);

DateTime? _toDateOrNull(dynamic t) =>
    (t is Timestamp) ? t.toDate() : null;

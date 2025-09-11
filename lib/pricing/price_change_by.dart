import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:luckygo_admin/global.dart'; // uses negara, negeri

class PriceChangeBy extends StatelessWidget {
  const PriceChangeBy({super.key});

  @override
  Widget build(BuildContext context) {
    if (negara.isEmpty || negeri.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Price Changes')),
        body: const Center(
          child: Text('Missing negara/negeri. Please set region first.'),
        ),
      );
    }

    final col = FirebaseFirestore.instance
        .collection(negara)
        .doc(negeri)
        .collection('information')
        .doc('item_price')
        .collection('changed_by');

    return Scaffold(
      appBar: AppBar(title: const Text('Price Changes')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: col.orderBy('changed_at', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? const [];

          if (docs.isEmpty) {
            return const Center(child: Text('No changes yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();

              final ts = data['changed_at'];
              final dt = (ts is Timestamp) ? ts.toDate() : null;

              final changedBy = (data['changed_by'] as String?)?.trim() ?? '';
              final changes = (data['changes'] as Map<String, dynamic>?) ?? {};
              final changeKeys = changes.keys.toList()..sort();

              return Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date
                      Row(
                        children: [
                          const Icon(Icons.event, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _formatDateLabel(dt) ?? d.id, // fallback to docId if no timestamp
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Who
                      Row(
                        children: [
                          const Icon(Icons.person, size: 18),
                          const SizedBox(width: 8),
                          Text('Price update by: ${changedBy.isEmpty ? '-' : changedBy}'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 10),

                      // Changes list
                      if (changeKeys.isEmpty)
                        const Text('No item details recorded.')
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: changeKeys.map((k) {
                            final v = changes[k];
                            final before = (v is Map && v['before'] != null) ? v['before'] : null;
                            final after  = (v is Map && v['after']  != null) ? v['after']  : null;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Item name
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      k,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Before → After
                                  Expanded(
                                    flex: 3,
                                    child: Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        _pill('bf: ${_fmtNum(before)}'),
                                        const Text('→'),
                                        _pill('af: ${_fmtNum(after)}'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Helpers

  static String _fmtNum(dynamic v) {
    if (v == null) return '-';
    if (v is num) {
      // Show integers without decimals; otherwise 2 dp
      if (v == v.roundToDouble()) return v.toInt().toString();
      return v.toStringAsFixed(2);
    }
    return v.toString();
  }

  static String? _formatDateLabel(DateTime? dt) {
    if (dt == null) return null;
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yyyy = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy  $hh:$min';
  }

  static Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.blue.withOpacity(0.08),
        border: Border.all(color: Colors.blue.withOpacity(0.25)),
      ),
      child: Text(text),
    );
  }
}

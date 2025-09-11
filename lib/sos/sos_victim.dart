// sos_victim.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:luckygo_admin/global.dart'; // provides negara, negeri, loggedUser, fullname
import 'package:url_launcher/url_launcher.dart';

class SosVictim extends StatefulWidget {
  const SosVictim({super.key});

  @override
  State<SosVictim> createState() => _SosVictimState();
}

class _SosVictimState extends State<SosVictim> {
  final Set<String> _busy = {}; // track per-card busy state

  @override
  Widget build(BuildContext context) {
    final n = negara;
    final s = negeri;

    return Scaffold(
      appBar: AppBar(title: const Text('SOS Victims')),
      body: (n == null || s == null || n.isEmpty || s.isEmpty)
          ? const Center(child: Text('Missing negara/negeri in global.dart'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(n)
                  .doc(s)
                  .collection('help_center')
                  .doc('SOS')
                  .collection('sos_data')
                  .where('sos_solved', isEqualTo: false)
                  // .orderBy('trigger_time', descending: true) // add index first
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No active SOS.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _buildSosCard(context, docs[i]),
                );
              },
            ),
    );
  }

  Widget _buildSosCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    // New structure fields
    final String dName = (data['driver_name'] as String?)?.trim() ?? '';
    final String dPhone = (data['driver_phone'] as String?)?.trim() ?? '';
    final String pName = (data['passenger_name'] as String?)?.trim() ?? '';
    final String pPhone = (data['passenger_phone'] as String?)?.trim() ?? '';

    final String triggerBy = ((data['trigger_by'] as String?) ?? '').toLowerCase();
    final dynamic trigTimeRaw = data['trigger_time']; // Timestamp | String | DateTime
    final bool solved = (data['sos_solved'] as bool?) ?? false;

    final String driverIsCalling = (data['driver_is_calling'] as String?)?.trim() ?? '';
    final String adminRemark = (data['admin_remark'] as String?) ?? '';

    // Optional coords (keep Track button working if present)
    final double? driverLat = _toDouble(data['driver_lat']);
    final double? driverLng = _toDouble(data['driver_lng']);
    final double? passengerLat = _toDouble(data['passenger_lat']);
    final double? passengerLng = _toDouble(data['passenger_lng']);

    // Determine sender/opponent from trigger_by
    final bool triggeredByDriver = triggerBy == 'driver';
    final String senderRole = triggeredByDriver ? 'driver' : 'passenger';
    final String senderName = triggeredByDriver ? dName : pName;
    final String senderPhone = triggeredByDriver ? dPhone : pPhone;

    final String otherRole = triggeredByDriver ? 'passenger' : 'driver';
    final String otherName = triggeredByDriver ? pName : dName;
    final String otherPhone = triggeredByDriver ? pPhone : dPhone;

    // Track coords preference: show sender coords first, fallback to the other
    double? trackLat, trackLng;
    if (senderRole == 'driver') {
      trackLat = driverLat ?? passengerLat;
      trackLng = driverLng ?? passengerLng;
    } else {
      trackLat = passengerLat ?? driverLat;
      trackLng = passengerLng ?? driverLng;
    }
    final bool canTrack = trackLat != null && trackLng != null;

    // Time display
    final String dateText = _fmtDynamicTime(trigTimeRaw) ?? '-';

    final isBusy = _busy.contains(doc.id);
    final remarkCtrl = TextEditingController(text: adminRemark);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: date + status chip + trigger chip
            Row(
              children: [
                Expanded(
                  child: Text(
                    dateText,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(text: solved ? 'SOLVED' : 'ACTIVE', solved: solved),
                const SizedBox(width: 6),
                if (triggerBy.isNotEmpty)
                  Chip(
                    label: Text('TRIGGER: ${triggerBy.toUpperCase()}'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Optional "driver_is_calling"
            if (driverIsCalling.isNotEmpty) ...[
              _kv('Driver is calling', driverIsCalling),
              const SizedBox(height: 4),
            ],

            // Sender (who triggered)
            _kv('Sender', senderRole.toUpperCase()),
            Row(children: [
              Expanded(child: _kv('Name', senderName.isEmpty ? '-' : senderName)),
              _CallCopyRow(phone: senderPhone),
            ]),
            const Divider(height: 18),

            // Other party
            _kv('Other party', otherRole.toUpperCase()),
            Row(children: [
              Expanded(child: _kv('Name', otherName.isEmpty ? '-' : otherName)),
              _CallCopyRow(phone: otherPhone),
            ]),

            const SizedBox(height: 12),

            // Admin remark editor
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: remarkCtrl,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Admin remark…',
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: isBusy
                          ? null
                          : () async {
                              await _updateDoc(
                                context,
                                doc.reference,
                                {
                                  // Save only → do NOT touch sos_solved
                                  'admin_remark': remarkCtrl.text.trim(),
                                  'adminId': fullname ?? loggedUser ?? 'admin',
                                  'admin_response_time': FieldValue.serverTimestamp(),
                                  'updatedAt': FieldValue.serverTimestamp(),
                                },
                              );
                            },
                      icon: const Icon(Icons.save),
                      tooltip: 'Save remark',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Track (optional)
                TextButton.icon(
                  onPressed: (!isBusy && canTrack)
                      ? () => _onTrack(trackLat!, trackLng!)
                      : null,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Track'),
                ),
                const SizedBox(width: 8),

                // Mark Solved (only here we set sos_solved: true)
                FilledButton.icon(
                  onPressed: isBusy || solved
                      ? null
                      : () async {
                          await _updateDoc(
                            context,
                            doc.reference,
                            {
                              'sos_solved': true,
                              'solved_time': FieldValue.serverTimestamp(),
                              'adminId': loggedUser,
                              'updatedAt': FieldValue.serverTimestamp(),
                            },
                          );
                        },
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Solved'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateDoc(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> payload,
  ) async {
    setState(() => _busy.add(ref.id));

    // Use the same root navigator to open & close the spinner
    final navigator = Navigator.of(context, rootNavigator: true);

    // Show blocking spinner
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Material(
          color: Colors.transparent,
          child: SizedBox(width: 52, height: 52, child: CircularProgressIndicator()),
        ),
      ),
    );

    String? errorMsg;
    try {
      await ref.update(payload);
    } catch (e) {
      errorMsg = e.toString();
    } finally {
      // Always close spinner and clear busy
      if (mounted) {
        // Close only if that root navigator can pop (dialog still present)
        try {
          if (navigator.canPop()) {
            navigator.pop();
          }
        } catch (_) {}
        if (errorMsg == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Updated successfully.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Update failed: $errorMsg')),
          );
        }
        setState(() => _busy.remove(ref.id));
      }
    }
  }

  Future<void> _onTrack(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    // Copy to clipboard as a convenience
    await Clipboard.setData(ClipboardData(text: '$lat,$lng'));

    // Try launching external maps
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Fallback: try in-app webview
      await launchUrl(uri, mode: LaunchMode.inAppWebView);
    }
  }

  // ---------- small helpers ----------

  double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return null;
  }

  String? _fmtDynamicTime(dynamic v) {
    try {
      if (v is Timestamp) {
        return DateFormat('yyyy-MM-dd HH:mm').format(v.toDate().toLocal());
      }
      if (v is DateTime) {
        return DateFormat('yyyy-MM-dd HH:mm').format(v.toLocal());
      }
      if (v is String) {
        final parsed = DateTime.tryParse(v);
        if (parsed != null) {
          return DateFormat('yyyy-MM-dd HH:mm').format(parsed.toLocal());
        }
        return v; // keep human text
      }
    } catch (_) {}
    return null;
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$k:',
              style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final bool solved;
  const _StatusChip({required this.text, required this.solved});

  @override
  Widget build(BuildContext context) {
    final ok = solved || text.toLowerCase() == 'solved';
    final color = ok ? Colors.green : (text.toLowerCase() == 'active' ? Colors.orange : Colors.grey);
    return Chip(
      label: Text(text.toUpperCase()),
      backgroundColor: color.withOpacity(0.12),
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _CallCopyRow extends StatelessWidget {
  final String phone;
  const _CallCopyRow({required this.phone});

  String _digits(String v) => v.replaceAll(RegExp(r'\D'), '');

  @override
  Widget build(BuildContext context) {
    final hasPhone = phone.trim().isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Call',
          onPressed: hasPhone
              ? () async {
                  final tel = _digits(phone);
                  if (tel.isEmpty) return;
                  final uri = Uri.parse('tel:$tel');
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              : null,
          icon: const Icon(Icons.phone),
        ),
        IconButton(
          tooltip: 'Copy',
          onPressed: hasPhone
              ? () async {
                  await Clipboard.setData(ClipboardData(text: _digits(phone)));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Phone copied')),
                    );
                  }
                }
              : null,
          icon: const Icon(Icons.copy),
        ),
      ],
    );
  }
}

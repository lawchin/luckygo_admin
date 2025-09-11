// driver_registration_details.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:luckygo_admin/global.dart';

class DriverRegistrationDetails extends StatefulWidget {
  final String driverId;
  const DriverRegistrationDetails({super.key, required this.driverId});

  @override
  State<DriverRegistrationDetails> createState() => _DriverRegistrationDetailsState();
}

class _DriverRegistrationDetailsState extends State<DriverRegistrationDetails> {
  final Map<String, bool> _checked = {}; // key = base (e.g. 'psv', 'ic', 'selfie')
  bool _busy = false;

  // Keep scroll position (no LateInitializationError on hot reload)
  ScrollController? _scrollController;
  ScrollController get _sc =>
      _scrollController ??= ScrollController(keepScrollOffset: true);

  // Only the bottom bar listens to this so we don't rebuild the whole page
  final ValueNotifier<int> _checkedTrueCount = ValueNotifier<int>(0);

  @override
  void dispose() {
    _scrollController?.dispose();
    _checkedTrueCount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = negara;
    final s = negeri;

    return Scaffold(
      appBar: AppBar(title: Text('Registration Details • ${widget.driverId}')),
      body: (n == null || s == null || n.isEmpty || s.isEmpty)
          ? const Center(child: Text('Missing negara/negeri.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(n)
                  .doc(s)
                  .collection('driver_account')
                  .doc(widget.driverId)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final doc = snap.data;
                if (doc == null || !doc.exists) {
                  return const Center(child: Text('Record not found.'));
                }

                final data = doc.data()!;
                final regEntries = data.entries.where((e) => e.key.startsWith('reg_')).toList();

                final imageEntries = regEntries
                    .where((e) =>
                        e.key.endsWith('_image_url') &&
                        (e.value is String) &&
                        (e.value as String).trim().isNotEmpty)
                    .toList()
                  ..sort((a, b) => _titleFromImageKey(a.key).compareTo(_titleFromImageKey(b.key)));

                // Ensure _checked has entries for all images (do not change existing values)
                for (final img in imageEntries) {
                  final base = img.key
                      .replaceFirst('reg_', '')
                      .replaceFirst(RegExp(r'_image_url$'), '');
                  _checked.putIfAbsent(base, () => false);
                }
                // Sync initial count for bottom bar (first build or after stream change)
                _checkedTrueCount.value = _checked.values.where((v) => v).length;

                return SingleChildScrollView(
                  key: const PageStorageKey<String>('driver_reg_details_scroll'),
                  controller: _sc,
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _headerMeta(context, data),
                      const SizedBox(height: 8),

                      // One Card per image item (Title, Row(image, Column(label/value, checkbox)))
                      ...imageEntries.map((img) {
                        final key = img.key; // e.g., reg_psv_image_url
                        final url = (img.value ?? '').toString();
                        final base = key
                            .replaceFirst('reg_', '')
                            .replaceFirst(RegExp(r'_image_url$'), '');
                        final title = _titleFromImageKey(key);

                        final expiryKey = 'reg_${base}_expiry';
                        final expiryValue = data[expiryKey];

                        final right = _rightColumnFor(base, data, expiryValue);

                        return Card(
                          elevation: 2,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          margin: const EdgeInsets.only(bottom: 14),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Title top center
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Center(
                                    child: Text(
                                      title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),

                                // Row(image, column(custom label, custom value, checkbox))
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // LEFT: Tappable Image
                                    InkWell(
                                      onTap: () => _openImageViewer(context, url),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          width: 180,
                                          height: 120,
                                          color: Colors.black12,
                                          child: Image.network(
                                            url,
                                            fit: BoxFit.cover,
                                            loadingBuilder: (ctx, child, progress) {
                                              if (progress == null) return child;
                                              return const Center(
                                                child: SizedBox(
                                                  width: 28,
                                                  height: 28,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                ),
                                              );
                                            },
                                            errorBuilder: (_, __, ___) => const Center(
                                              child: Icon(Icons.broken_image_outlined),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // RIGHT: Column(custom label, custom value, checkbox)
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(right.label,
                                              style: const TextStyle(fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 6),
                                          SelectableText(right.value),
                                          const SizedBox(height: 6),

                                          // 👉 Only this subtree rebuilds when ticking the box
                                          StatefulBuilder(
                                            builder: (ctx, setStateCard) {
                                              return Align(
                                                alignment: Alignment.centerRight,
                                                child: CheckboxListTile(
                                                  contentPadding: EdgeInsets.zero,
                                                  dense: true,
                                                  title: const Text('Checked'),
                                                  controlAffinity:
                                                      ListTileControlAffinity.trailing,
                                                  value: _checked[base] ?? false,
                                                  onChanged: (v) {
                                                    final newVal = v ?? false;
                                                    if (_checked[base] == newVal) return;

                                                    // Update data
                                                    _checked[base] = newVal;
                                                    // Update this tile only
                                                    setStateCard(() {});
                                                    // Update bottom bar without rebuilding page
                                                    _checkedTrueCount.value =
                                                        _checked.values.where((x) => x).length;
                                                  },
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),

                      // Keep last card visible above buttons
                      const SizedBox(height: 60),
                    ],
                  ),
                );
              },
            ),

      // Sticky bottom action bar (listens to checked count only)
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        final reasonController = TextEditingController();
                        return AlertDialog(
                          title: const Text('What is the reason'),
                          content: TextField(
                            controller: reasonController,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              hintText: 'Enter reason',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(8)),
                              ),
                              isDense: true,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final reason = reasonController.text.trim();
                                      Navigator.of(context).pop();
                                      if (reason.isEmpty) return;

                                      final n = negara, s = negeri;
                                      if (n == null || s == null || n.isEmpty || s.isEmpty) return;

                                      setState(() => _busy = true);
                                      _showSpinner();

                                      try {
                                        await FirebaseFirestore.instance
                                            .collection(n)
                                            .doc(s)
                                            .collection('driver_account')
                                            .doc(widget.driverId)
                                            .update({
                                          'registration_remark_timestamp':
                                              FieldValue.serverTimestamp(),
                                          'registration_remark': reason,
                                        });

                                        _hideSpinner();
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Driver rejected.')),
                                          );
                                        }
                                      } catch (e) {
                                        _hideSpinner();
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Failed to reject: $e')),
                                          );
                                        }
                                      } finally {
                                        if (mounted) setState(() => _busy = false);
                                      }
                                    },
                              child: const Text('Reject'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Text('Reject', style: TextStyle(color: Colors.red)),
                ),
              ),
              const SizedBox(width: 12),

              // ✅ Only this button subtree rebuilds when counts change
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: _checkedTrueCount,
                  builder: (context, checkedCount, _) {
                    final total = _checked.length;
                    final allChecked = total > 0 && checkedCount == total;
                    final remaining = total - checkedCount;

                    return ElevatedButton(
                      onPressed: _busy ? null : () => _handleApprovePressed(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: allChecked ? Colors.green : Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        allChecked
                            ? 'Approve'
                            : (remaining > 0 ? 'Approve ($remaining left)' : 'Approve'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Guards for Approve ----------
  bool _areAllChecked() {
    if (_checked.isEmpty) return false; // require at least 1 item
    for (final v in _checked.values) {
      if (v != true) return false;
    }
    return true;
  }

  List<String> _uncheckedTitles() {
    final titles = <String>[];
    for (final e in _checked.entries) {
      if (e.value != true) {
        titles.add(_titleFromImageKey('reg_${e.key}_image_url'));
      }
    }
    return titles;
  }

  Future<void> _handleApprovePressed() async {
    if (_checked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No documents to verify. Please check items before approving.')),
      );
      return;
    }
    if (!_areAllChecked()) {
      final missing = _uncheckedTitles();
      final msg = (missing.isEmpty)
          ? 'Please make sure all checkboxes are ticked before approving.'
          : 'Please tick all items before approving. Missing: ${missing.take(3).join(', ')}'
            '${missing.length > 3 ? '…' : ''}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    await _onApprove(); // will navigate back to NewDriver() on success
  }

  // ---------- Full-screen image viewer ----------
  Future<void> _openImageViewer(BuildContext context, String url) async {
    final u = url.trim();
    if (u.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image URL is empty')),
      );
      return;
    }
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (_, __, ___) => _ImageFullScreen(url: u),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  // ---------- Right-column label/value rules ----------
  _RightColumn _rightColumnFor(String base, Map<String, dynamic> data, dynamic expiryValue) {
    switch (base) {
      case 'car_back':
        return _RightColumn(label: 'Back Side', value: _formatDateAny(expiryValue));
      case 'car_front':
        return _RightColumn(label: 'Front Side', value: _formatDateAny(expiryValue));
      case 'ic':
        return _RightColumn(label: 'IC number', value: (data['reg_ic_no'] ?? '-').toString());
      case 'selfie':
        return _RightColumn(label: 'Fullname', value: (data['fullname'] ?? '-').toString());
      default:
        return _RightColumn(label: 'Expiry', value: _formatDateAny(expiryValue));
    }
  }

  // ---------- Actions ----------
  Future<void> _onApprove() async {
    final n = negara, s = negeri;
    if (n == null || s == null || n.isEmpty || s.isEmpty) return;

    setState(() => _busy = true);
    _showSpinner();

    try {
      await FirebaseFirestore.instance
          .collection(n)
          .doc(s)
          .collection('driver_account')
          .doc(widget.driverId)
          .update({
        'registration_approved': true,
        'registration_approved_timestamp': FieldValue.serverTimestamp(),
      });

      _hideSpinner();

      if (!mounted) return;

      // Back to list
      Navigator.of(context).pop();

    } catch (e) {
      _hideSpinner();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to approve: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSpinner() {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Material(
          color: Colors.transparent,
          child: SizedBox(width: 64, height: 64, child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  void _hideSpinner() {
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // ---------- Header & helpers ----------
  Widget _headerMeta(BuildContext context, Map<String, dynamic> data) {
    final fullname = (data['fullname'] ?? '').toString();
    final phone = _toPhoneFromEmail((data['email'] ?? '').toString());
    final registerDate = _formatDateAny(data['register_date'] ?? data['created_at']);

    return Wrap(
      runSpacing: 8,
      spacing: 12,
      children: [
        _chip('Register Date', registerDate),
        if (fullname.isNotEmpty) _chip('Fullname', fullname),
        if (phone.isNotEmpty) _chip('Phone', phone),
      ],
    );
  }

  static String _toPhoneFromEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceFirst(RegExp(r'@driver\.com$', caseSensitive: false), '');
  }

  static String _titleFromImageKey(String key) {
    var base = key.replaceFirst('reg_', '').replaceFirst(RegExp(r'_image_url$'), '');
    switch (base) {
      case 'psv':
        return 'PSV';
      case 'road_tax':
        return 'Road Tax';
      case 'insurance':
        return 'Insurance';
      case 'drivers_license':
        return "Driver's License";
      case 'ic':
        return 'IC';
      case 'selfie':
        return 'Selfie';
      case 'car_front':
        return 'Car Front';
      case 'car_back':
        return 'Car Back';
      default:
        return base
            .split('_')
            .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
    }
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

  static Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _RightColumn {
  final String label;
  final String value;
  _RightColumn({required this.label, required this.value});
}

class _ImageFullScreen extends StatelessWidget {
  final String url;
  const _ImageFullScreen({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      width: 42,
                      height: 42,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 80,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: InkWell(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Text(
                    '×',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// // driver_registration_details.dart
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'package:luckygo_admin/global.dart';

// class DriverRegistrationDetails extends StatefulWidget {
//   final String driverId;
//   const DriverRegistrationDetails({super.key, required this.driverId});

//   @override
//   State<DriverRegistrationDetails> createState() => _DriverRegistrationDetailsState();
// }

// class _DriverRegistrationDetailsState extends State<DriverRegistrationDetails> {
//   final Map<String, bool> _checked = {}; // key = base (e.g. 'psv', 'ic', 'selfie')
//   bool _busy = false;

//   // ✅ Nullable + lazy init to avoid LateInitializationError on hot reload
//   ScrollController? _scrollController;

//   ScrollController get _sc =>
//       _scrollController ??= ScrollController(keepScrollOffset: true);

//   @override
//   void dispose() {
//     _scrollController?.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final n = negara;
//     final s = negeri;

//     // Derived: are all items checked?
//     final bool allChecked = _areAllChecked();
//     final int totalChecks = _checked.length;
//     final int remaining = totalChecks - _checked.values.where((v) => v).length;

//     return Scaffold(
//       appBar: AppBar(title: Text('Registration Details • ${widget.driverId}')),
//       body: (n == null || s == null || n.isEmpty || s.isEmpty)
//           ? const Center(child: Text('Missing negara/negeri.'))
//           : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
//               stream: FirebaseFirestore.instance
//                   .collection(n)
//                   .doc(s)
//                   .collection('driver_account')
//                   .doc(widget.driverId)
//                   .snapshots(),
//               builder: (context, snap) {
//                 if (snap.connectionState == ConnectionState.waiting) {
//                   return const Center(child: CircularProgressIndicator());
//                 }
//                 if (snap.hasError) {
//                   return Center(child: Text('Error: ${snap.error}'));
//                 }
//                 final doc = snap.data;
//                 if (doc == null || !doc.exists) {
//                   return const Center(child: Text('Record not found.'));
//                 }

//                 final data = doc.data()!;
//                 final regEntries = data.entries.where((e) => e.key.startsWith('reg_')).toList();

//                 final imageEntries = regEntries
//                     .where((e) =>
//                         e.key.endsWith('_image_url') &&
//                         (e.value is String) &&
//                         (e.value as String).trim().isNotEmpty)
//                     .toList()
//                   ..sort((a, b) => _titleFromImageKey(a.key).compareTo(_titleFromImageKey(b.key)));

//                 return SingleChildScrollView(
//                   key: const PageStorageKey<String>('driver_reg_details_scroll'),
//                   controller: _sc, // ✅ persistent controller
//                   primary: false,
//                   physics: const ClampingScrollPhysics(),
//                   padding: const EdgeInsets.all(16),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.stretch,
//                     children: [
//                       _headerMeta(context, data),
//                       const SizedBox(height: 8),

//                       // One Card per image item (Title, Row(image, Column(label/value, checkbox)))
//                       ...imageEntries.map((img) {
//                         final key = img.key; // e.g., reg_psv_image_url
//                         final url = (img.value ?? '').toString();
//                         final base = key
//                             .replaceFirst('reg_', '')
//                             .replaceFirst(RegExp(r'_image_url$'), '');
//                         final title = _titleFromImageKey(key);

//                         final expiryKey = 'reg_${base}_expiry';
//                         final expiryValue = data[expiryKey];

//                         final right = _rightColumnFor(base, data, expiryValue);

//                         // ensure a checkbox entry exists for this base
//                         _checked.putIfAbsent(base, () => false);

//                         return Card(
//                           elevation: 2,
//                           clipBehavior: Clip.antiAlias,
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(16),
//                           ),
//                           margin: const EdgeInsets.only(bottom: 14),
//                           child: Padding(
//                             padding: const EdgeInsets.all(14),
//                             child: Column(
//                               crossAxisAlignment: CrossAxisAlignment.stretch,
//                               children: [
//                                 // Title top center
//                                 Padding(
//                                   padding: const EdgeInsets.only(bottom: 10),
//                                   child: Center(
//                                     child: Text(
//                                       title,
//                                       style: Theme.of(context)
//                                           .textTheme
//                                           .titleMedium
//                                           ?.copyWith(fontWeight: FontWeight.w700),
//                                     ),
//                                   ),
//                                 ),

//                                 // Row(image, column(custom label, custom value, checkbox))
//                                 Row(
//                                   crossAxisAlignment: CrossAxisAlignment.start,
//                                   children: [
//                                     // LEFT: Tappable Image
//                                     InkWell(
//                                       onTap: () => _openImageViewer(context, url),
//                                       child: ClipRRect(
//                                         borderRadius: BorderRadius.circular(12),
//                                         child: Container(
//                                           width: 180,
//                                           height: 120,
//                                           color: Colors.black12,
//                                           child: Image.network(
//                                             url,
//                                             fit: BoxFit.cover,
//                                             loadingBuilder: (ctx, child, progress) {
//                                               if (progress == null) return child;
//                                               return const Center(
//                                                 child: SizedBox(
//                                                   width: 28,
//                                                   height: 28,
//                                                   child: CircularProgressIndicator(strokeWidth: 2),
//                                                 ),
//                                               );
//                                             },
//                                             errorBuilder: (_, __, ___) => const Center(
//                                               child: Icon(Icons.broken_image_outlined),
//                                             ),
//                                           ),
//                                         ),
//                                       ),
//                                     ),
//                                     const SizedBox(width: 12),

//                                     // RIGHT: Column(custom label, custom value, checkbox)
//                                     Expanded(
//                                       child: Column(
//                                         crossAxisAlignment: CrossAxisAlignment.start,
//                                         children: [
//                                           Text(right.label,
//                                               style: const TextStyle(fontWeight: FontWeight.w700)),
//                                           const SizedBox(height: 6),
//                                           SelectableText(right.value),
//                                           const SizedBox(height: 6),
//                                           Align(
//                                             alignment: Alignment.centerRight,
//                                             child: CheckboxListTile(
//                                               contentPadding: EdgeInsets.zero,
//                                               dense: true,
//                                               title: const Text('Checked'),
//                                               controlAffinity: ListTileControlAffinity.trailing,
//                                               value: _checked[base],
//                                               onChanged: (v) {
//                                                 // ✅ Keep current scroll offset and restore after rebuild
//                                                 final has = _sc.hasClients;
//                                                 final double offset = has ? _sc.offset : 0.0;

//                                                 setState(() {
//                                                   _checked[base] = v ?? false;
//                                                 });

//                                                 if (has) {
//                                                   WidgetsBinding.instance.addPostFrameCallback((_) {
//                                                     if (_sc.hasClients) {
//                                                       final max = _sc.position.maxScrollExtent;
//                                                       final clamped = offset.clamp(0.0, max).toDouble();
//                                                       _sc.jumpTo(clamped);
//                                                     }
//                                                   });
//                                                 }
//                                               },
//                                             ),
//                                           ),
//                                         ],
//                                       ),
//                                     ),
//                                   ],
//                                 ),
//                               ],
//                             ),
//                           ),
//                         );
//                       }),

//                       // Keep last card visible above buttons
//                       const SizedBox(height: 60),
//                     ],
//                   ),
//                 );
//               },
//             ),

//       // Sticky bottom action bar
//       bottomNavigationBar: SafeArea(
//         top: false,
//         child: Padding(
//           padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
//           child: Row(
//             children: [
//               Expanded(
//                 child: OutlinedButton(
//                   onPressed: () {
//                     showDialog(
//                       context: context,
//                       builder: (context) {
//                         final reasonController = TextEditingController();

//                         return AlertDialog(
//                           title: const Text('What is the reason'),
//                           content: TextField(
//                             controller: reasonController,
//                             maxLines: 6,
//                             decoration: const InputDecoration(
//                               hintText: 'Enter reason',
//                               border: OutlineInputBorder(
//                                 borderRadius: BorderRadius.all(Radius.circular(8)),
//                               ),
//                               isDense: true,
//                             ),
//                           ),
//                           actions: [
//                             TextButton(
//                               onPressed: () => Navigator.of(context).pop(),
//                               child: const Text('Cancel'),
//                             ),
//                             ElevatedButton(
//                               onPressed: _busy
//                                   ? null
//                                   : () async {
//                                       final reason = reasonController.text.trim();
//                                       Navigator.of(context).pop();
//                                       if (reason.isEmpty) return;

//                                       final n = negara, s = negeri;
//                                       if (n == null || s == null || n.isEmpty || s.isEmpty) return;

//                                       setState(() => _busy = true);
//                                       _showSpinner();

//                                       try {
//                                         await FirebaseFirestore.instance
//                                             .collection(n)
//                                             .doc(s)
//                                             .collection('driver_account')
//                                             .doc(widget.driverId)
//                                             .update({
//                                           'registration_remark_timestamp': FieldValue.serverTimestamp(),
//                                           'registration_remark': reason,
//                                         });

//                                         _hideSpinner();
//                                         if (mounted) {
//                                           ScaffoldMessenger.of(context).showSnackBar(
//                                             const SnackBar(content: Text('Driver rejected.')),
//                                           );
//                                         }
//                                       } catch (e) {
//                                         _hideSpinner();
//                                         if (mounted) {
//                                           ScaffoldMessenger.of(context).showSnackBar(
//                                             SnackBar(content: Text('Failed to reject: $e')),
//                                           );
//                                         }
//                                       } finally {
//                                         if (mounted) setState(() => _busy = false);
//                                       }
//                                     },
//                               child: const Text('Reject'),
//                             ),
//                           ],
//                         );
//                       },
//                     );
//                   },
//                   style: OutlinedButton.styleFrom(
//                     side: const BorderSide(color: Colors.red),
//                   ),
//                   child: const Text('Reject', style: TextStyle(color: Colors.red)),
//                 ),
//               ),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: ElevatedButton(
//                   onPressed: _busy ? null : () => _handleApprovePressed(),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: allChecked ? Colors.green : Colors.grey,
//                     foregroundColor: Colors.white,
//                   ),
//                   child: Text(allChecked
//                       ? 'Approve'
//                       : (remaining > 0 ? 'Approve ($remaining left)' : 'Approve')),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   // ---------- Guards for Approve ----------
//   bool _areAllChecked() {
//     if (_checked.isEmpty) return false; // require at least 1 item
//     for (final v in _checked.values) {
//       if (v != true) return false;
//     }
//     return true;
//   }

//   List<String> _uncheckedTitles() {
//     final titles = <String>[];
//     for (final e in _checked.entries) {
//       if (e.value != true) {
//         titles.add(_titleFromImageKey('reg_${e.key}_image_url'));
//       }
//     }
//     return titles;
//   }

//   Future<void> _handleApprovePressed() async {
//     if (_checked.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('No documents to verify. Please check items before approving.')),
//       );
//       return;
//     }
//     if (!_areAllChecked()) {
//       final missing = _uncheckedTitles();
//       final msg = (missing.isEmpty)
//           ? 'Please make sure all checkboxes are ticked before approving.'
//           : 'Please tick all items before approving. Missing: ${missing.take(3).join(', ')}'
//             '${missing.length > 3 ? '…' : ''}';
//       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
//       return;
//     }

//     await _onApprove(); // will navigate back to NewDriver() on success
//   }

//   // ---------- Full-screen image viewer (route-based; safer than showGeneralDialog) ----------
//   Future<void> _openImageViewer(BuildContext context, String url) async {
//     final u = url.trim();
//     if (u.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Image URL is empty')),
//       );
//       return;
//     }
//     await Navigator.of(context).push(
//       PageRouteBuilder(
//         opaque: true,
//         transitionDuration: const Duration(milliseconds: 180),
//         reverseTransitionDuration: const Duration(milliseconds: 120),
//         pageBuilder: (_, __, ___) => _ImageFullScreen(url: u),
//         transitionsBuilder: (_, anim, __, child) =>
//             FadeTransition(opacity: anim, child: child),
//       ),
//     );
//   }

//   // ---------- Right-column label/value rules ----------
//   _RightColumn _rightColumnFor(String base, Map<String, dynamic> data, dynamic expiryValue) {
//     switch (base) {
//       case 'car_back':
//         return _RightColumn(label: 'Back Side', value: _formatDateAny(expiryValue));
//       case 'car_front':
//         return _RightColumn(label: 'Front Side', value: _formatDateAny(expiryValue));
//       case 'ic':
//         return _RightColumn(label: 'IC number', value: (data['reg_ic_no'] ?? '-').toString());
//       case 'selfie':
//         return _RightColumn(label: 'Fullname', value: (data['fullname'] ?? '-').toString());
//       default:
//         return _RightColumn(label: 'Expiry', value: _formatDateAny(expiryValue));
//     }
//   }

//   // ---------- Actions ----------
//   Future<void> _onApprove() async {
//     final n = negara, s = negeri;
//     if (n == null || s == null || n.isEmpty || s.isEmpty) return;

//     setState(() => _busy = true);
//     _showSpinner();

//     try {
//       await FirebaseFirestore.instance
//           .collection(n)
//           .doc(s)
//           .collection('driver_account')
//           .doc(widget.driverId)
//           .update({
//         'registration_approved': true,
//         'registration_approved_timestamp': FieldValue.serverTimestamp(),
//       });

//       _hideSpinner();

//       if (!mounted) return;

//       // ✅ Go back to the previous page (NewDriver list)
//       Navigator.of(context).pop();

//     } catch (e) {
//       _hideSpinner();
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Failed to approve: $e')),
//         );
//       }
//     } finally {
//       if (mounted) setState(() => _busy = false);
//     }
//   }

//   void _showSpinner() {
//     showDialog(
//       context: context,
//       useRootNavigator: true,
//       barrierDismissible: false,
//       builder: (_) => const Center(
//         child: Material(
//           color: Colors.transparent,
//           child: SizedBox(width: 64, height: 64, child: CircularProgressIndicator()),
//         ),
//       ),
//     );
//   }

//   void _hideSpinner() {
//     if (Navigator.of(context, rootNavigator: true).canPop()) {
//       Navigator.of(context, rootNavigator: true).pop();
//     }
//   }

//   // ---------- Header & helpers ----------
//   Widget _headerMeta(BuildContext context, Map<String, dynamic> data) {
//     final fullname = (data['fullname'] ?? '').toString();
//     final phone = _toPhoneFromEmail((data['email'] ?? '').toString());
//     final registerDate = _formatDateAny(data['register_date'] ?? data['created_at']);

//     return Wrap(
//       runSpacing: 8,
//       spacing: 12,
//       children: [
//         _chip('Register Date', registerDate),
//         if (fullname.isNotEmpty) _chip('Fullname', fullname),
//         if (phone.isNotEmpty) _chip('Phone', phone),
//       ],
//     );
//   }

//   static String _toPhoneFromEmail(String email) {
//     final trimmed = email.trim();
//     if (trimmed.isEmpty) return '';
//     return trimmed.replaceFirst(RegExp(r'@driver\.com$', caseSensitive: false), '');
//   }

//   static String _titleFromImageKey(String key) {
//     var base = key.replaceFirst('reg_', '').replaceFirst(RegExp(r'_image_url$'), '');
//     switch (base) {
//       case 'psv':
//         return 'PSV';
//       case 'road_tax':
//         return 'Road Tax';
//       case 'insurance':
//         return 'Insurance';
//       case 'drivers_license':
//         return "Driver's License";
//       case 'ic':
//         return 'IC';
//       case 'selfie':
//         return 'Selfie';
//       case 'car_front':
//         return 'Car Front';
//       case 'car_back':
//         return 'Car Back';
//       default:
//         return base
//             .split('_')
//             .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
//             .join(' ');
//     }
//   }

//   static String _formatDateAny(dynamic v) {
//     if (v == null) return '-';
//     if (v is Timestamp) return _formatYMDHMS(v.toDate());
//     if (v is DateTime) return _formatYMDHMS(v);

//     if (v is String) {
//       final s = v.trim();
//       if (s.isEmpty) return '-';
//       final dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
//       if (dateOnly.hasMatch(s)) return s;
//       final parsed = DateTime.tryParse(s);
//       if (parsed != null) return _formatYMDHMS(parsed);
//       final re = RegExp(r'^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})');
//       final m = re.firstMatch(s);
//       if (m != null) return '${m.group(1)} ${m.group(2)}';
//       return s;
//     }
//     return v.toString();
//   }

//   static String _formatYMDHMS(DateTime dt) {
//     dt = dt.toLocal();
//     String two(int n) => n.toString().padLeft(2, '0');
//     final y = dt.year.toString().padLeft(4, '0');
//     final mo = two(dt.month);
//     final d = two(dt.day);
//     final h = two(dt.hour);
//     final mi = two(dt.minute);
//     final s = two(dt.second);
//     return '$y-$mo-$d $h:$mi:$s';
//   }

//   static Widget _chip(String label, String value) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//       decoration: BoxDecoration(
//         color: Colors.black12,
//         borderRadius: BorderRadius.circular(999),
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
//           Text(value, style: const TextStyle(fontSize: 12)),
//         ],
//       ),
//     );
//   }
// }

// class _RightColumn {
//   final String label;
//   final String value;
//   _RightColumn({required this.label, required this.value});
// }

// /// Fullscreen image viewer with pinch-zoom and a red "×" close button.
// /// Uses a dedicated route (Scaffold) to avoid dialog layout/assertion issues.
// class _ImageFullScreen extends StatelessWidget {
//   final String url;
//   const _ImageFullScreen({required this.url});

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: Stack(
//         children: [
//           Positioned.fill(
//             child: Center(
//               child: InteractiveViewer(
//                 minScale: 0.5,
//                 maxScale: 4.0,
//                 child: Image.network(
//                   url,
//                   fit: BoxFit.contain,
//                   filterQuality: FilterQuality.high,
//                   loadingBuilder: (ctx, child, progress) {
//                     if (progress == null) return child;
//                     return const SizedBox(
//                       width: 42,
//                       height: 42,
//                       child: CircularProgressIndicator(strokeWidth: 2),
//                     );
//                   },
//                   errorBuilder: (_, __, ___) => const Icon(
//                     Icons.broken_image_outlined,
//                     color: Colors.white54,
//                     size: 80,
//                   ),
//                 ),
//               ),
//             ),
//           ),
//           SafeArea(
//             child: Align(
//               alignment: Alignment.topRight,
//               child: Padding(
//                 padding: const EdgeInsets.all(12),
//                 child: InkWell(
//                   onTap: () => Navigator.of(context).maybePop(),
//                   child: const Text(
//                     '×',
//                     style: TextStyle(
//                       color: Colors.red,
//                       fontSize: 36,
//                       fontWeight: FontWeight.w900,
//                       height: 1.0,
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }


// // driver_registration_details.dart
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'package:luckygo_admin/global.dart';

// class DriverRegistrationDetails extends StatefulWidget {
//   final String driverId;
//   const DriverRegistrationDetails({super.key, required this.driverId});

//   @override
//   State<DriverRegistrationDetails> createState() => _DriverRegistrationDetailsState();
// }

// class _DriverRegistrationDetailsState extends State<DriverRegistrationDetails> {
//   final Map<String, bool> _checked = {}; // key = base (e.g. 'psv', 'ic', 'selfie')
//   bool _busy = false;

//   @override
//   Widget build(BuildContext context) {
//     final n = negara;
//     final s = negeri;

//     // Derived: are all items checked?
//     final bool allChecked = _areAllChecked();
//     final int totalChecks = _checked.length;
//     final int remaining = totalChecks - _checked.values.where((v) => v).length;

//     return Scaffold(
//       appBar: AppBar(title: Text('Registration Details • ${widget.driverId}')),
//       body: (n == null || s == null || n.isEmpty || s.isEmpty)
//           ? const Center(child: Text('Missing negara/negeri.'))
//           : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
//               stream: FirebaseFirestore.instance
//                   .collection(n)
//                   .doc(s)
//                   .collection('driver_account')
//                   .doc(widget.driverId)
//                   .snapshots(),
//               builder: (context, snap) {
//                 if (snap.connectionState == ConnectionState.waiting) {
//                   return const Center(child: CircularProgressIndicator());
//                 }
//                 if (snap.hasError) {
//                   return Center(child: Text('Error: ${snap.error}'));
//                 }
//                 final doc = snap.data;
//                 if (doc == null || !doc.exists) {
//                   return const Center(child: Text('Record not found.'));
//                 }

//                 final data = doc.data()!;
//                 final regEntries = data.entries.where((e) => e.key.startsWith('reg_')).toList();

//                 final imageEntries = regEntries
//                     .where((e) =>
//                         e.key.endsWith('_image_url') &&
//                         (e.value is String) &&
//                         (e.value as String).trim().isNotEmpty)
//                     .toList()
//                   ..sort((a, b) => _titleFromImageKey(a.key).compareTo(_titleFromImageKey(b.key)));

//                 return SingleChildScrollView(
//                   padding: const EdgeInsets.all(16),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.stretch,
//                     children: [
//                       _headerMeta(context, data),
//                       const SizedBox(height: 8),

//                       // One Card per image item (Title, Row(image, Column(label/value, checkbox)))
//                       ...imageEntries.map((img) {
//                         final key = img.key; // e.g., reg_psv_image_url
//                         final url = (img.value ?? '').toString();
//                         final base = key
//                             .replaceFirst('reg_', '')
//                             .replaceFirst(RegExp(r'_image_url$'), '');
//                         final title = _titleFromImageKey(key);

//                         final expiryKey = 'reg_${base}_expiry';
//                         final expiryValue = data[expiryKey];

//                         final right = _rightColumnFor(base, data, expiryValue);

//                         // ensure a checkbox entry exists for this base
//                         _checked.putIfAbsent(base, () => false);

//                         return Card(
//                           elevation: 2,
//                           clipBehavior: Clip.antiAlias,
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(16),
//                           ),
//                           margin: const EdgeInsets.only(bottom: 14),
//                           child: Padding(
//                             padding: const EdgeInsets.all(14),
//                             child: Column(
//                               crossAxisAlignment: CrossAxisAlignment.stretch,
//                               children: [
//                                 // Title top center
//                                 Padding(
//                                   padding: const EdgeInsets.only(bottom: 10),
//                                   child: Center(
//                                     child: Text(
//                                       title,
//                                       style: Theme.of(context)
//                                           .textTheme
//                                           .titleMedium
//                                           ?.copyWith(fontWeight: FontWeight.w700),
//                                     ),
//                                   ),
//                                 ),

//                                 // Row(image, column(custom label, custom value, checkbox))
//                                 Row(
//                                   crossAxisAlignment: CrossAxisAlignment.start,
//                                   children: [
//                                     // LEFT: Tappable Image
//                                     GestureDetector(
//                                       onTap: () => _openImageViewer(context, url),
//                                       child: ClipRRect(
//                                         borderRadius: BorderRadius.circular(12),
//                                         child: Container(
//                                           width: 180,
//                                           height: 120,
//                                           color: Colors.black12,
//                                           child: Image.network(
//                                             url,
//                                             fit: BoxFit.cover,
//                                             errorBuilder: (_, __, ___) => const Center(
//                                               child: Icon(Icons.broken_image_outlined),
//                                             ),
//                                           ),
//                                         ),
//                                       ),
//                                     ),
//                                     const SizedBox(width: 12),

//                                     // RIGHT: Column(custom label, custom value, checkbox)
//                                     Expanded(
//                                       child: Column(
//                                         crossAxisAlignment: CrossAxisAlignment.start,
//                                         children: [
//                                           Text(right.label,
//                                               style: const TextStyle(fontWeight: FontWeight.w700)),
//                                           const SizedBox(height: 6),
//                                           SelectableText(right.value),
//                                           const SizedBox(height: 6),
//                                           Align(
//                                             alignment: Alignment.centerRight,
//                                             child: CheckboxListTile(
//                                               contentPadding: EdgeInsets.zero,
//                                               dense: true,
//                                               title: const Text('Checked'),
//                                               controlAffinity: ListTileControlAffinity.trailing,
//                                               value: _checked[base],
//                                               onChanged: (v) {
//                                                 setState(() => _checked[base] = v ?? false);
//                                               },
//                                             ),
//                                           ),
//                                         ],
//                                       ),
//                                     ),
//                                   ],
//                                 ),
//                               ],
//                             ),
//                           ),
//                         );
//                       }),

//                       // Keep last card visible above buttons
//                       const SizedBox(height: 60),
//                     ],
//                   ),
//                 );
//               },
//             ),

//       // Sticky bottom action bar
//       bottomNavigationBar: SafeArea(
//         top: false,
//         child: Padding(
//           padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
//           child: Row(
//             children: [
//               Expanded(
//                 child: OutlinedButton(
//                   onPressed: () {
//                     showDialog(
//                       context: context,
//                       builder: (context) {
//                         final reasonController = TextEditingController();

//                         return AlertDialog(
//                           title: const Text('What is the reason'),
//                           content: TextField(
//                             controller: reasonController,
//                             maxLines: 6,
//                             decoration: const InputDecoration(
//                               hintText: 'Enter reason',
//                               border: OutlineInputBorder(
//                                 borderRadius: BorderRadius.all(Radius.circular(8)),
//                               ),
//                               isDense: true,
//                             ),
//                           ),
//                           actions: [
//                             TextButton(
//                               onPressed: () => Navigator.of(context).pop(),
//                               child: const Text('Cancel'),
//                             ),
//                             ElevatedButton(
//                               onPressed: _busy
//                                   ? null
//                                   : () async {
//                                       final reason = reasonController.text.trim();
//                                       Navigator.of(context).pop();
//                                       if (reason.isEmpty) return;

//                                       final n = negara, s = negeri;
//                                       if (n == null || s == null || n.isEmpty || s.isEmpty) return;

//                                       setState(() => _busy = true);
//                                       _showSpinner();

//                                       try {
//                                         await FirebaseFirestore.instance
//                                             .collection(n)
//                                             .doc(s)
//                                             .collection('driver_account')
//                                             .doc(widget.driverId)
//                                             .update({
//                                           'registration_remark_timestamp': FieldValue.serverTimestamp(),
//                                           'registration_remark': reason,
//                                         });

//                                         _hideSpinner();
//                                         if (mounted) {
//                                           ScaffoldMessenger.of(context).showSnackBar(
//                                             const SnackBar(content: Text('Driver rejected.')),
//                                           );
//                                         }
//                                       } catch (e) {
//                                         _hideSpinner();
//                                         if (mounted) {
//                                           ScaffoldMessenger.of(context).showSnackBar(
//                                             SnackBar(content: Text('Failed to reject: $e')),
//                                           );
//                                         }
//                                       } finally {
//                                         if (mounted) setState(() => _busy = false);
//                                       }
//                                     },
//                               child: const Text('Reject'),
//                             ),
//                           ],
//                         );
//                       },
//                     );
//                   },
//                   style: OutlinedButton.styleFrom(
//                     side: const BorderSide(color: Colors.red),
//                   ),
//                   child: const Text('Reject', style: TextStyle(color: Colors.red)),
//                 ),
//               ),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: ElevatedButton(
//                   onPressed: _busy ? null : () => _handleApprovePressed(),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: allChecked ? Colors.green : Colors.grey,
//                     foregroundColor: Colors.white,
//                   ),
//                   child: Text(allChecked
//                       ? 'Approve'
//                       : (remaining > 0 ? 'Approve ($remaining left)' : 'Approve')),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   // ---------- Guards for Approve ----------
//   bool _areAllChecked() {
//     if (_checked.isEmpty) return false; // require at least 1 item
//     for (final v in _checked.values) {
//       if (v != true) return false;
//     }
//     return true;
//   }

//   List<String> _uncheckedTitles() {
//     final titles = <String>[];
//     for (final e in _checked.entries) {
//       if (e.value != true) {
//         titles.add(_titleFromImageKey('reg_${e.key}_image_url'));
//       }
//     }
//     return titles;
//   }

//   Future<void> _handleApprovePressed() async {
//     if (_checked.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('No documents to verify. Please check items before approving.')),
//       );
//       return;
//     }
//     if (!_areAllChecked()) {
//       final missing = _uncheckedTitles();
//       final msg = (missing.isEmpty)
//           ? 'Please make sure all checkboxes are ticked before approving.'
//           : 'Please tick all items before approving. Missing: ${missing.take(3).join(', ')}'
//             '${missing.length > 3 ? '…' : ''}';
//       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
//       return;
//     }

//     await _onApprove(); // will navigate back to NewDriver() on success
//   }

//   // ---------- Full-screen image viewer ----------
//   void _openImageViewer(BuildContext context, String url) {
//     showGeneralDialog(
//       context: context,
//       barrierLabel: 'Image',
//       barrierDismissible: true,
//       barrierColor: Colors.black.withOpacity(0.9),
//       pageBuilder: (_, __, ___) {
//         return Stack(
//           children: [
//             Positioned.fill(
//               child: Container(
//                 color: Colors.black,
//                 child: Center(
//                   child: InteractiveViewer(
//                     minScale: 0.5,
//                     maxScale: 4.0,
//                     child: Image.network(
//                       url,
//                       fit: BoxFit.contain,
//                       errorBuilder: (_, __, ___) => const Icon(
//                         Icons.broken_image_outlined,
//                         color: Colors.white54,
//                         size: 80,
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//             SafeArea(
//               child: Align(
//                 alignment: Alignment.topRight,
//                 child: Padding(
//                   padding: const EdgeInsets.all(12),
//                   child: InkWell(
//                     onTap: () => Navigator.of(context, rootNavigator: true).pop(),
//                     child: const Text(
//                       '×',
//                       style: TextStyle(
//                         color: Colors.red,
//                         fontSize: 36,
//                         fontWeight: FontWeight.w900,
//                         height: 1.0,
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         );
//       },
//       transitionBuilder: (_, anim, __, child) =>
//           FadeTransition(opacity: anim, child: child),
//     );
//   }

//   // ---------- Right-column label/value rules ----------
//   _RightColumn _rightColumnFor(String base, Map<String, dynamic> data, dynamic expiryValue) {
//     switch (base) {
//       case 'car_back':
//         return _RightColumn(label: 'Back Side', value: _formatDateAny(expiryValue));
//       case 'car_front':
//         return _RightColumn(label: 'Front Side', value: _formatDateAny(expiryValue));
//       case 'ic':
//         return _RightColumn(label: 'IC number', value: (data['reg_ic_no'] ?? '-').toString());
//       case 'selfie':
//         return _RightColumn(label: 'Fullname', value: (data['fullname'] ?? '-').toString());
//       default:
//         return _RightColumn(label: 'Expiry', value: _formatDateAny(expiryValue));
//     }
//   }

//   // ---------- Actions ----------
//   Future<void> _onApprove() async {
//     final n = negara, s = negeri;
//     if (n == null || s == null || n.isEmpty || s.isEmpty) return;

//     setState(() => _busy = true);
//     _showSpinner();

//     try {
//       await FirebaseFirestore.instance
//           .collection(n)
//           .doc(s)
//           .collection('driver_account')
//           .doc(widget.driverId)
//           .update({
//         'registration_approved': true,
//         'registration_approved_timestamp': FieldValue.serverTimestamp(),
//       });

//       _hideSpinner();

//       if (!mounted) return;

//       // Optional: brief success toast here (it may vanish on pop)
//       // ScaffoldMessenger.of(context).showSnackBar(
//       //   const SnackBar(content: Text('Driver approved.')),
//       // );

//       // ✅ Go back to the previous page (NewDriver list)
//       Navigator.of(context).pop(); // return to NewDriver()

//     } catch (e) {
//       _hideSpinner();
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Failed to approve: $e')),
//         );
//       }
//     } finally {
//       if (mounted) setState(() => _busy = false);
//     }
//   }

//   void _showSpinner() {
//     showDialog(
//       context: context,
//       useRootNavigator: true,
//       barrierDismissible: false,
//       builder: (_) => const Center(
//         child: Material(
//           color: Colors.transparent,
//           child: SizedBox(width: 64, height: 64, child: CircularProgressIndicator()),
//         ),
//       ),
//     );
//   }

//   void _hideSpinner() {
//     if (Navigator.of(context, rootNavigator: true).canPop()) {
//       Navigator.of(context, rootNavigator: true).pop();
//     }
//   }

//   // ---------- Header & helpers ----------
//   Widget _headerMeta(BuildContext context, Map<String, dynamic> data) {
//     final fullname = (data['fullname'] ?? '').toString();
//     final phone = _toPhoneFromEmail((data['email'] ?? '').toString());
//     final registerDate = _formatDateAny(data['register_date'] ?? data['created_at']);

//     return Wrap(
//       runSpacing: 8,
//       spacing: 12,
//       children: [
//         _chip('Register Date', registerDate),
//         if (fullname.isNotEmpty) _chip('Fullname', fullname),
//         if (phone.isNotEmpty) _chip('Phone', phone),
//       ],
//     );
//   }

//   static String _toPhoneFromEmail(String email) {
//     final trimmed = email.trim();
//     if (trimmed.isEmpty) return '';
//     return trimmed.replaceFirst(RegExp(r'@driver\.com$', caseSensitive: false), '');
//   }

//   static String _titleFromImageKey(String key) {
//     var base = key.replaceFirst('reg_', '').replaceFirst(RegExp(r'_image_url$'), '');
//     switch (base) {
//       case 'psv':
//         return 'PSV';
//       case 'road_tax':
//         return 'Road Tax';
//       case 'insurance':
//         return 'Insurance';
//       case 'drivers_license':
//         return "Driver's License";
//       case 'ic':
//         return 'IC';
//       case 'selfie':
//         return 'Selfie';
//       case 'car_front':
//         return 'Car Front';
//       case 'car_back':
//         return 'Car Back';
//       default:
//         return base
//             .split('_')
//             .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
//             .join(' ');
//     }
//   }

//   static String _formatDateAny(dynamic v) {
//     if (v == null) return '-';
//     if (v is Timestamp) return _formatYMDHMS(v.toDate());
//     if (v is DateTime) return _formatYMDHMS(v);

//     if (v is String) {
//       final s = v.trim();
//       if (s.isEmpty) return '-';
//       final dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
//       if (dateOnly.hasMatch(s)) return s;
//       final parsed = DateTime.tryParse(s);
//       if (parsed != null) return _formatYMDHMS(parsed);
//       final re = RegExp(r'^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})');
//       final m = re.firstMatch(s);
//       if (m != null) return '${m.group(1)} ${m.group(2)}';
//       return s;
//     }
//     return v.toString();
//   }

//   static String _formatYMDHMS(DateTime dt) {
//     dt = dt.toLocal();
//     String two(int n) => n.toString().padLeft(2, '0');
//     final y = dt.year.toString().padLeft(4, '0');
//     final mo = two(dt.month);
//     final d = two(dt.day);
//     final h = two(dt.hour);
//     final mi = two(dt.minute);
//     final s = two(dt.second);
//     return '$y-$mo-$d $h:$mi:$s';
//   }

//   static Widget _chip(String label, String value) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//       decoration: BoxDecoration(
//         color: Colors.black12,
//         borderRadius: BorderRadius.circular(999),
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
//           Text(value, style: const TextStyle(fontSize: 12)),
//         ],
//       ),
//     );
//   }
// }

// class _RightColumn {
//   final String label;
//   final String value;
//   _RightColumn({required this.label, required this.value});
// }

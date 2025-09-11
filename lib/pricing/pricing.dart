// pricing.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luckygo_admin/LandingPage/home_page.dart';
import 'package:luckygo_admin/global.dart'; // uses negara, negeri

class Pricing extends StatefulWidget {
  const Pricing({super.key});

  @override
  State<Pricing> createState() => _PricingState();
}

class _PricingState extends State<Pricing> {
  Map<String, dynamic> _data = {};
  final Map<String, TextEditingController> _controllers = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (negara == null || negeri == null || negara!.isEmpty || negeri!.isEmpty) {
        throw 'Missing negara / negeri in global.dart';
      }

      final doc = await FirebaseFirestore.instance
          .collection(negara!)
          .doc(negeri)
          .collection('information')
          .doc('item_price')
          .get();

      if (!doc.exists) {
        setState(() {
          _data = {};
          _loading = false;
          _error = 'item_price document not found.';
        });
        return;
      }

      final map = doc.data() as Map<String, dynamic>? ?? {};
      _data = Map<String, dynamic>.from(map);

      // Create/reset controllers (keep any already created to preserve cursor)
      for (final key in _data.keys) {
        _controllers.putIfAbsent(key, () => TextEditingController());
        // do not set text; we want hint to show current value, and text empty = no change
        _controllers[key]!.text = '';
      }

      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

Future<void> _save() async {
  // Collect changed fields (non-empty inputs)
  final Map<String, dynamic> updates = {};
  final List<String> invalids = [];

  for (final entry in _controllers.entries) {
    final key = entry.key;
    final text = entry.value.text.trim();
    if (text.isEmpty) continue; // no change for this field

    final original = _data[key];
    final parsed = _parseToNum(text);
    if (parsed == null) {
      invalids.add(key);
      continue;
    }

    // try to preserve int if original was int and input has no decimal
    final dynamic value = (original is int && !_hasDecimal(text))
        ? parsed.toInt()
        : parsed.toDouble();

    // (optional) skip if same value as before:
    // if (original == value) continue;

    updates[key] = value;
  }

  if (invalids.isNotEmpty) {
    final sample = invalids.take(5).join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Invalid number for: $sample')),
    );
    return;
  }
  if (updates.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No changes to save.')),
    );
    return;
  }

  setState(() => _saving = true);

  // Block UI with a tiny spinner dialog (non-dismissible)
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: Material(
        color: Colors.transparent,
        child: SizedBox(width: 56, height: 56, child: CircularProgressIndicator()),
      ),
    ),
  );

  try {
    final fs = FirebaseFirestore.instance;
    final ref = fs
        .collection(negara!)
        .doc(negeri)
        .collection('information')
        .doc('item_price');

    // 👇 Build the audit detail BEFORE mutating _data
    final Map<String, Map<String, dynamic>> changeDetails = {};
    updates.forEach((k, newVal) {
      changeDetails[k] = {
        'before': _data[k],
        'after': newVal,
      };
    });

    // Write both updates + audit in a single atomic batch
    final batch = fs.batch();

    batch.update(ref, updates);

    final changeDocId = '${getFormattedDate()}($fullname)';
    final auditRef = ref.collection('changed_by').doc(changeDocId);
    batch.set(auditRef, {
      'changed_by': fullname,
      'changed_at': FieldValue.serverTimestamp(),
      'changes': changeDetails,        // ← only the fields that changed
      'keys': updates.keys.toList(),   // (optional) convenience index
    });

    await batch.commit();

    // Clear controllers & refresh local view
    for (final c in _controllers.values) {
      c.clear();
    }
    // Merge updates into local cache to refresh hints immediately
    updates.forEach((k, v) => _data[k] = v);

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // close spinner
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved successfully.')),
      );
    }
  } catch (e) {
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // close spinner
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    final n = negara;
    final s = negeri;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pricing'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _fetch,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: (n == null || s == null || n.isEmpty || s.isEmpty)
          ? const Center(child: Text('Missing negara/negeri in global.dart'))
          : _buildBody(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: (_loading || _saving) ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Save Changes'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_data.isEmpty) {
      return const Center(child: Text('No pricing fields found.'));
    }

    // Sort keys for consistent UI (group-esque by prefix, then lexicographically)
    final keys = _data.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: keys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final k = keys[i];
        final v = _data[k];

        // Show only numeric fields
        if (v is! num) {
          return _nonNumericTile(k, v);
        }

        return _priceFieldTile(
          keyName: k,
          currentValue: v,
          controller: _controllers[k]!,
        );
      },
    );
  }

  Widget _priceFieldTile({
    required String keyName,
    required num currentValue,
    required TextEditingController controller,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Field label (use the raw key, or prettify if you want)
            Text(
              keyName,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
              ],
              decoration: InputDecoration(
                hintText: '$currentValue', // 👈 current price as hint
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            controller.clear();
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            const Text(
              'Leave empty to keep current value',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // If the document has some non-numeric fields, we render them as read-only rows.
  Widget _nonNumericTile(String keyName, dynamic value) {
    return Card(
      color: Colors.grey.shade50,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                keyName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '$value',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  num? _parseToNum(String text) {
    if (text.isEmpty) return null;
    try {
      if (_hasDecimal(text)) {
        return double.parse(text);
      } else {
        return int.parse(text);
      }
    } catch (_) {
      // fallback: try double
      try {
        return double.parse(text);
      } catch (_) {
        return null;
      }
    }
  }

  bool _hasDecimal(String s) => s.contains('.') || s.contains(',');

}

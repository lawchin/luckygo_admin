import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:luckygo_admin/global.dart';

class ActiveDeposit extends StatelessWidget {
  const ActiveDeposit({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection(negara)
        .doc(negeri)
        .collection('information')
        .doc('banking')
        .collection('deposit_data')
        .where('deposit_needed_process', isEqualTo: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Active Deposit')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          // Sort by deposit_date DESC (in-memory to avoid composite index)
          final docs = snap.data?.docs.toList() ?? [];
          docs.sort((a, b) {
            final ta = a.data()['deposit_date'];
            final tb = b.data()['deposit_date'];
            final da = ta is Timestamp ? ta.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            final db = tb is Timestamp ? tb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da);
          });

          if (docs.isEmpty) {
            return const Center(child: Text('No deposit data found.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();

              final name   = (data['name'] ?? '') as String;
              final phone  = ((data['phone'] ?? data['uid'] ?? '') as String);
              final amount = (data['deposit_amount'] ?? '') as String;
              final who    = (data['driver_or_passenger'] ?? '') as String;
              final receiptImg    = (data['receipt_image_url'] ?? '') as String;
              final last4dPhone    = (data['last_4d_phone'] ?? '') as String;

              // date: dd-MM-yyyy HH:mm
              String dateText = '—';
              final dd = data['deposit_date'];
              if (dd is Timestamp) {
                final dt = dd.toDate().toLocal();
                dateText =
                    '${dt.day.toString().padLeft(2, '0')}-'
                    '${dt.month.toString().padLeft(2, '0')}-'
                    '${dt.year} ${dt.hour.toString().padLeft(2, '0')}:'
                    '${dt.minute.toString().padLeft(2, '0')}';
              }

              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.monetization_on),
                  ),
                  title: Text(
                    dateText,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, height: 1),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (who.isNotEmpty)
                        Text(who, style: const TextStyle(height: 1.2, color: Colors.blue, fontWeight: FontWeight.w500)),
                      if (name.isNotEmpty)
                        Text(name, style: const TextStyle(height: 1.6, fontWeight: FontWeight.bold)),
                      if (phone.isNotEmpty)
                        Text(phone, style: const TextStyle(height: 0.2)),
                    ],
                  ),
                  trailing: Text(
                    amount,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                  ),
                  onTap: () => _showDetailsSheet(context, doc.id, data),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Parse "amount" reliably (supports "3", "3.50", "RM 3,200.50")
double _parseAmount(String? s) {
  if (s == null) return 0.0;
  final cleaned = s.replaceAll(RegExp(r'[^\d\.\-]'), '');
  return double.tryParse(cleaned) ?? 0.0;
}

/// Approve/Reject helper (single place that updates all relevant docs).
Future<void> approveOrRejectDeposit({
  required String docId,
  required String phone,
  required String name,
  required String who,
  required String receiptImg,
  required String last4dPhone,
  required String status, // "Approved" | "Rejected"
  String? remark,
  required String amount,
  bool verifiedAmount = false,
  bool verifiedLast4 = false,
}) async {
  final db = FirebaseFirestore.instance;
  final root = db.collection(negara).doc(negeri);
  final depositerColl = (who.toLowerCase() == 'passenger') ? 'passenger_account' : 'driver_account';
  final depositDoc   = root.collection('information').doc('banking').collection('deposit_data').doc(docId);
  final accountDoc   = root.collection(depositerColl).doc(phone);

  

  

  final historyDoc   = accountDoc.collection('deposit_history').doc(docId);
  final transactionDoc   = accountDoc.collection('transaction_history').doc(docId);
  final notificationDoc   = accountDoc.collection('notification_page').doc(docId);
  final approvalDoc   = root.collection('information').doc('banking').collection('admin_approval').doc(docId);

  final amt = _parseAmount(amount);

  final batch = db.batch();

  // Update the central deposit record
  batch.update(depositDoc, {
    'admin_remark': remark ?? '',
    'admin_remark_date': FieldValue.serverTimestamp(),
    'deposit_status': status,
    'deposit_needed_process': false,
    'verified_amount': verifiedAmount,
    'verified_last4': verifiedLast4,
    'updated_at': FieldValue.serverTimestamp(),
  });

  // Mirror to depositer's deposit_history (merge to avoid missing-doc error)
  batch.set(historyDoc, {
    'admin_remark': remark ?? '',
    'admin_remark_date': FieldValue.serverTimestamp(),
    'deposit_status': status,
    'updated_at': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  batch.set(transactionDoc, {
    'transaction_amount': amount,
    'transaction_date': FieldValue.serverTimestamp(),
    'transaction_description': 'Deposit',
    'transaction_money_in': true
  }, SetOptions(merge: true));

  batch.set(notificationDoc, {
    'notification_date': FieldValue.serverTimestamp(),
    'notification_description': 'Hello $name, We would like to inform you that your deposit worth $currency${_parseAmount(amount).toStringAsFixed(2)} has been credited to your account successfully.\n\nThank you for using Lucky Go.',
    'notification_seen': false
  }, SetOptions(merge: true));

  batch.set(approvalDoc, {
    'admin_remark': 'Admin has checked both last 4 digits:  $last4dPhone and amount: $amount respectively',
    'admin_remark_date': FieldValue.serverTimestamp(),
    'receipt_image_url': receiptImg,
    'responsible_admin': loggedUser,
  }, SetOptions(merge: true));

  // Only add balance when Approved
  if (status.toLowerCase() == 'approved') {
    batch.update(accountDoc, {
      'account_balance': FieldValue.increment(amt),
    });
  }

  await batch.commit();
}

// Reject dialog: ask for remark, then call approveOrRejectDeposit(...)
Future<void> _showRejectDialog(
  BuildContext context,
  String docId, {
  required String name,
  required String phone,
  required String who,
  required String amount,
  required String receiptImg, // <-- add this
  required String last4dPhone,
}) async {
  final controller = TextEditingController();

  final remark = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Add remark'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Type remark (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Submit Rejection'),
          ),
        ],
      );
    },
  );

  if (remark != null) {
    await approveOrRejectDeposit(
      receiptImg: receiptImg,// WHY IS THI RED?
      last4dPhone: last4dPhone,
      docId: docId,
      phone: phone,
      name: name,
      who: who,
      status: 'Rejected',
      remark: remark,
      amount: amount,
      verifiedAmount: false,
      verifiedLast4: false,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deposit marked as rejected')),
      );
      Navigator.pop(context); // close the bottom sheet
    }
  }
}








/// Bottom sheet with verification UI.
void _showDetailsSheet(
  BuildContext context,
  String docId,
  Map<String, dynamic> data,
) {
  final name   = (data['name'] ?? '') as String;
  final phone  = ((data['phone'] ?? data['uid'] ?? '') as String);
  final last4  = (data['last_4d_phone'] ?? '') as String;
  final amount = (data['deposit_amount'] ?? '') as String;
  final imgUrl = (data['receipt_image_url'] ?? '') as String;
  final who    = (data['driver_or_passenger'] ?? '') as String;
  final receiptImg    = (data['receipt_image_url'] ?? '') as String;
  final last4dPhone    = (data['last_4d_phone'] ?? '') as String;

  String dateText = '—';
  final dd = data['deposit_date'];
  if (dd is Timestamp) {
    final dt = dd.toDate().toLocal();
    dateText =
        '${dt.day.toString().padLeft(2, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.year} ${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          final bottomSafe = MediaQuery.of(context).viewPadding.bottom;

          bool amtChecked = false;
          bool last4Checked = false;

          return StatefulBuilder(
            builder: (context, setState) {
              final approveEnabled = amtChecked && last4Checked;

              return SafeArea(
                top: false,
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomSafe),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Deposit Verification',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),

                      LabelValueRow(label: 'Deposit Date', value: dateText),
                      const SizedBox(height: 8),
                      LabelValueRow(label: 'Name', value: name),
                      const SizedBox(height: 8),
                      LabelValueRow(label: 'Phone Number', value: phone),

                      const SizedBox(height: 14),
                      const Text('Receipt Image', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final double w = constraints.maxWidth;
                          final double h = (w * 0.62).clamp(160.0, 420.0);
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: w,
                              height: h,
                              color: Colors.black12.withOpacity(.05),
                              child: imgUrl.isNotEmpty
                                  ? InkWell(
                                      onTap: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => Dialog(
                                            insetPadding: const EdgeInsets.all(16),
                                            child: InteractiveViewer(
                                              child: Image.network(imgUrl, fit: BoxFit.contain),
                                            ),
                                          ),
                                        );
                                      },
                                      child: Image.network(imgUrl, fit: BoxFit.contain),
                                    )
                                  : const Center(
                                      child: Icon(Icons.image_not_supported_outlined,
                                          size: 40, color: Colors.black38),
                                    ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 16),
                      const Text('DEPOSIT AMOUNT',
                          style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: amount,
                              readOnly: true,
                              decoration: const InputDecoration(
                                isDense: true,
                                filled: true,
                                border: OutlineInputBorder(),
                              ),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Checkbox(
                            value: amtChecked,
                            onChanged: (v) => setState(() => amtChecked = v ?? false),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),
                      const Text('LAST 4 DIGITS (PHONE)',
                          style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: last4,
                              readOnly: true,
                              decoration: const InputDecoration(
                                isDense: true,
                                filled: true,
                                border: OutlineInputBorder(),
                              ),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Checkbox(
                            value: last4Checked,
                            onChanged: (v) => setState(() => last4Checked = v ?? false),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: 
                            
                            // OutlinedButton(
                            //   style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            //   onPressed: () => _showRejectDialog(
                            //     context,
                            //     docId,
                            //     name: name,
                            //     phone: phone,
                            //     who: who,
                            //     amount: amount,
                            //   ),
                            //   child: const Text('Reject'),
                            // ),


OutlinedButton(
  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
  onPressed: () => _showRejectDialog(
    context,
    docId,
    name: name,
    phone: phone,
    who: who,
    amount: amount,
    receiptImg: imgUrl, // <-- pass it here
    last4dPhone: last4dPhone,
  ),
  child: const Text('Reject'),
),



                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: approveEnabled
                                  ? () async {
                                      await approveOrRejectDeposit(
                                        receiptImg: imgUrl,
                                        last4dPhone: last4dPhone,
                                        docId: docId,
                                        phone: phone,
                                        name: name,
                                        who: who,
                                        status: 'Approved',
                                        remark: '',
                                        amount: amount,
                                        verifiedAmount: amtChecked,
                                        verifiedLast4: last4Checked,
                                      );
                                      if (context.mounted) Navigator.pop(context);
                                    }
                                  : null,
                              child: const Text('Approved'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    },
  );
}

/// Simple label/value row used in the details sheet.
class LabelValueRow extends StatelessWidget {
  final String label;
  final String value;
  const LabelValueRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}


// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:luckygo_admin/global.dart';

// class ActiveDeposit extends StatelessWidget {
//   const ActiveDeposit({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final query = FirebaseFirestore.instance
//         .collection(negara)
//         .doc(negeri)
//         .collection('information')
//         .doc('banking')
//         .collection('deposit_data')
//         .where('deposit_needed_process', isEqualTo: true);

//     return Scaffold(
//       appBar: AppBar(title: const Text('Active Deposit')),
//       body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//         stream: query.snapshots(),
//         builder: (context, snap) {
//           if (snap.connectionState == ConnectionState.waiting) {
//             return const Center(child: CircularProgressIndicator(strokeWidth: 2));
//           }
//           if (snap.hasError) {
//             return Center(child: Text('Error: ${snap.error}'));
//           }

//           // Sort by deposit_date DESC (in-memory -> avoids composite index)
//           final docs = snap.data?.docs.toList() ?? [];
//           docs.sort((a, b) {
//             final ta = a.data()['deposit_date'];
//             final tb = b.data()['deposit_date'];
//             final da = ta is Timestamp ? ta.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
//             final db = tb is Timestamp ? tb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
//             return db.compareTo(da);
//           });

//           if (docs.isEmpty) {
//             return const Center(child: Text('No deposit data found.'));
//           }

//           return ListView.separated(
//             padding: const EdgeInsets.all(12),
//             itemCount: docs.length,
//             separatorBuilder: (_, __) => const SizedBox(height: 8),
//             itemBuilder: (context, i) {
//               final doc = docs[i];
//               final data = doc.data();

//               final name   = (data['name'] ?? '') as String;
//               final phone  = ((data['phone'] ?? data['uid'] ?? '') as String);
//               final amount = (data['deposit_amount'] ?? '') as String;
//               final who    = (data['driver_or_passenger'] ?? '') as String;

//               // Date text: dd-MM-yyyy HH:mm
//               String dateText = '—';
//               final dd = data['deposit_date'];
//               if (dd is Timestamp) {
//                 final dt = dd.toDate().toLocal();
//                 dateText =
//                     '${dt.day.toString().padLeft(2, '0')}-'
//                     '${dt.month.toString().padLeft(2, '0')}-'
//                     '${dt.year} ${dt.hour.toString().padLeft(2, '0')}:'
//                     '${dt.minute.toString().padLeft(2, '0')}';
//               }

//               return Card(
//                 elevation: 2,
//                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                 child: ListTile(
//                   contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//                   leading: Container(
//                     width: 44,
//                     height: 44,
//                     decoration: BoxDecoration(
//                       color: Colors.blue.withOpacity(.08),
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                     child: const Icon(Icons.monetization_on),
//                   ),
//                   title: Text(
//                     dateText,
//                     style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, height: 1),
//                   ),
//                   subtitle: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       if (who.isNotEmpty)
//                         Text(who, style: const TextStyle(height: 1.2, color: Colors.blue, fontWeight: FontWeight.w500)),
//                       if (name.isNotEmpty)
//                         Text(name, style: const TextStyle(height: 1.6, fontWeight: FontWeight.bold)),
//                       if (phone.isNotEmpty)
//                         Text(phone, style: const TextStyle(height: 0.2)),
//                     ],
//                   ),
//                   trailing: Text(
//                     amount,
//                     textAlign: TextAlign.right,
//                     style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
//                   ),
//                   onTap: () => _showDetailsSheet(context, doc.id, data),
//                 ),
//               );
//             },
//           );
//         },
//       ),
//     );
//   }
// }

// /// Reject dialog: collects an optional remark, then updates Firestore.
// Future<void> _showRejectDialog(
//   BuildContext context,
//   String docId, {
//   required String name,
//   required String phone,
//   required String who,
//   required String amount,

// }) async {
//   final controller = TextEditingController();

//   final remark = await showDialog<String>(
//     context: context,
//     builder: (ctx) {
//       return AlertDialog(
//         title: const Text('Add remark'),
//         content: TextField(
//           controller: controller,
//           maxLines: 4,
//           decoration: const InputDecoration(
//             hintText: 'Type remark (optional)',
//             border: OutlineInputBorder(),
//           ),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(ctx),
//             child: const Text('Close'),
//           ),
//           ElevatedButton(
//             onPressed: () async {
//               String depositer = '';
//               await FirebaseFirestore.instance
//                   .collection(negara)
//                   .doc(negeri)
//                   .collection('information')
//                   .doc('banking')
//                   .collection('deposit_data')
//                   .doc(docId)
//                   .update({
//                 'admin_remark': controller.text.trim(),
//                 'admin_remark_date': FieldValue.serverTimestamp(),
//                 'deposit_status': 'Rejected',
//                 'deposit_needed_process': false,
//               });
//               if (who == 'Passenger'){
//                 depositer = 'passenger_account';
//               }else{depositer = 'driver_account';}
              
//               await FirebaseFirestore.instance
//                   .collection(negara)
//                   .doc(negeri)
//                   .collection(depositer)
//                   .doc(phone)
//                   .collection('deposit_history')
//                   .doc(docId)
//                   .update({
//                 'admin_remark': controller.text.trim(),
//                 'admin_remark_date': FieldValue.serverTimestamp(),
//                 'deposit_status': 'Rejected',
//                 // 'deposit_needed_process': false,
//               });
              
//               // await FirebaseFirestore.instance
//               //     .collection(negara)
//               //     .doc(negeri)
//               //     .collection(depositer)
//               //     .doc(phone)
//               //     .update({
//               //   'account_balance': double.parse(amount),
//               // });

//             },

//             child: const Text('Submit Rejection'),
//           ),
//         ],
//       );
//     },
//   );


// }

// Future<void> approveOrRejectDeposit({
//   required String phone,
//   required String who,
//   required String remark,
//   required String status,
//   required String amount,
// }) async {
//   String depositer = who == 'Passenger' ? 'passenger_account' : 'driver_account';

//   await FirebaseFirestore.instance
//       .collection(negara)
//       .doc(negeri)
//       .collection('information')
//       .doc('banking')
//       .collection('deposit_data')
//       .doc(phone)
//       .update({
//     'admin_remark': remark,
//     'admin_remark_date': FieldValue.serverTimestamp(),
//     'deposit_status': status,
//     'deposit_needed_process': false,
//   });

//   await FirebaseFirestore.instance
//       .collection(negara)
//       .doc(negeri)
//       .collection(depositer)
//       .doc(phone)
//       .collection('deposit_history')
//       .doc(phone)
//       .update({
//     'admin_remark': remark,
//     'admin_remark_date': FieldValue.serverTimestamp(),
//     'deposit_status': status,
//   });


//   await FirebaseFirestore.instance
//       .collection(negara)
//       .doc(negeri)
//       .collection(depositer)
//       .doc(phone)
//       .update({
//     'account_balance': double.parse(amount),
//   });
  
// }


// /// Bottom sheet with verification UI.
// void _showDetailsSheet(
//   BuildContext context,
//   String docId,
//   Map<String, dynamic> data,
// ) {
//   final name   = (data['name'] ?? '') as String;
//   final phone  = ((data['phone'] ?? data['uid'] ?? '') as String);
//   final last4  = (data['last_4d_phone'] ?? '') as String;
//   final amount = (data['deposit_amount'] ?? '') as String;
//   final imgUrl = (data['receipt_image_url'] ?? '') as String;
//   final who    = (data['driver_or_passenger'] ?? '') as String; // <-- add this

//   String dateText = '—';
//   final dd = data['deposit_date'];
//   if (dd is Timestamp) {
//     final dt = dd.toDate().toLocal();
//     dateText =
//         '${dt.day.toString().padLeft(2, '0')}-'
//         '${dt.month.toString().padLeft(2, '0')}-'
//         '${dt.year} ${dt.hour.toString().padLeft(2, '0')}:'
//         '${dt.minute.toString().padLeft(2, '0')}';
//   }

//   showModalBottomSheet(
//     context: context,
//     isScrollControlled: true,
//     showDragHandle: true,
//     shape: const RoundedRectangleBorder(
//       borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
//     ),
//     builder: (ctx) {
//       return DraggableScrollableSheet(
//         expand: false,
//         initialChildSize: 0.6,
//         minChildSize: 0.3,
//         maxChildSize: 0.95,
//         builder: (context, scrollController) {
//           final bottomSafe = MediaQuery.of(context).viewPadding.bottom;

//           bool amtChecked = false;
//           bool last4Checked = false;

//           return StatefulBuilder(
//             builder: (context, setState) {
//               final approveEnabled = amtChecked && last4Checked;

//               return SafeArea(
//                 top: false,
//                 child: SingleChildScrollView(
//                   controller: scrollController,
//                   padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomSafe),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       const Text('Deposit Verification',
//                           style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
//                       const SizedBox(height: 12),

//                       LabelValueRow(label: 'Deposit Date', value: dateText),
//                       const SizedBox(height: 8),
//                       LabelValueRow(label: 'Name', value: name),
//                       const SizedBox(height: 8),
//                       LabelValueRow(label: 'Phone Number', value: phone),

//                       const SizedBox(height: 14),
//                       const Text('Receipt Image', style: TextStyle(fontWeight: FontWeight.w600)),
//                       const SizedBox(height: 8),
//                       LayoutBuilder(
//                         builder: (context, constraints) {
//                           final double w = constraints.maxWidth;
//                           final double h = (w * 0.62).clamp(160.0, 420.0);
//                           return ClipRRect(
//                             borderRadius: BorderRadius.circular(12),
//                             child: Container(
//                               width: w,
//                               height: h,
//                               color: Colors.black12.withOpacity(.05),
//                               child: imgUrl.isNotEmpty
//                                   ? InkWell(
//                                       onTap: () {
//                                         showDialog(
//                                           context: context,
//                                           builder: (_) => Dialog(
//                                             insetPadding: const EdgeInsets.all(16),
//                                             child: InteractiveViewer(
//                                               child: Image.network(imgUrl, fit: BoxFit.contain),
//                                             ),
//                                           ),
//                                         );
//                                       },
//                                       child: Image.network(imgUrl, fit: BoxFit.contain),
//                                     )
//                                   : const Center(
//                                       child: Icon(Icons.image_not_supported_outlined,
//                                           size: 40, color: Colors.black38),
//                                     ),
//                             ),
//                           );
//                         },
//                       ),

//                       const SizedBox(height: 16),
//                       const Text('DEPOSIT AMOUNT',
//                           style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w700)),
//                       const SizedBox(height: 6),
//                       Row(
//                         children: [
//                           Expanded(
//                             child: TextFormField(
//                               initialValue: amount,
//                               readOnly: true,
//                               decoration: const InputDecoration(
//                                 isDense: true,
//                                 filled: true,
//                                 border: OutlineInputBorder(),
//                               ),
//                               style: const TextStyle(fontWeight: FontWeight.w600),
//                             ),
//                           ),
//                           const SizedBox(width: 12),
//                           Checkbox(
//                             value: amtChecked,
//                             onChanged: (v) => setState(() => amtChecked = v ?? false),
//                           ),
//                         ],
//                       ),

//                       const SizedBox(height: 14),
//                       const Text('LAST 4 DIGITS (PHONE)',
//                           style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w700)),
//                       const SizedBox(height: 6),
//                       Row(
//                         children: [
//                           Expanded(
//                             child: TextFormField(
//                               initialValue: last4,
//                               readOnly: true,
//                               decoration: const InputDecoration(
//                                 isDense: true,
//                                 filled: true,
//                                 border: OutlineInputBorder(),
//                               ),
//                               style: const TextStyle(fontWeight: FontWeight.w600),
//                             ),
//                           ),
//                           const SizedBox(width: 12),
//                           Checkbox(
//                             value: last4Checked,
//                             onChanged: (v) => setState(() => last4Checked = v ?? false),
//                           ),
//                         ],
//                       ),

//                       const SizedBox(height: 16),
//                       Row(
//                         children: [
//                           Expanded(
//                             child: OutlinedButton(
//                               onPressed: () => Navigator.pop(context),
//                               child: const Text('Close'),
//                             ),
//                           ),
//                           const SizedBox(width: 8),
//                           Expanded(
//                             child: OutlinedButton(
//                               style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
//                               onPressed: () => _showRejectDialog(
//                                 context,
//                                 docId,
//                                 name: name,
//                                 phone: phone,
//                                 who: who,
//                                 amount: amount
//                               ),
//                               child: const Text('Reject'),
//                             ),
//                           ),
//                           const SizedBox(width: 8),
//                           Expanded(
//                             child: ElevatedButton(
//                               onPressed: approveEnabled
//                                   ? () async {
//                                     approveOrRejectDeposit(phone: phone, who: who, remark: '', status: 'Approved', amount: amount);
//                                       if (context.mounted) Navigator.pop(context);
//                                     }
//                                   : null,
//                               child: const Text('Approve'),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//               );
//             },
//           );
//         },
//       );
//     },
//   );
// }

// /// Simple label/value row used in the details sheet.
// class LabelValueRow extends StatelessWidget {
//   final String label;
//   final String value;
//   const LabelValueRow({super.key, required this.label, required this.value});

//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       children: [
//         SizedBox(
//           width: 140,
//           child: Text(
//             label.toUpperCase(),
//             style: const TextStyle(
//               fontSize: 11,
//               color: Colors.black54,
//               fontWeight: FontWeight.w700,
//             ),
//             overflow: TextOverflow.ellipsis,
//           ),
//         ),
//         const SizedBox(width: 8),
//         Expanded(
//           child: Text(
//             value,
//             style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
//           ),
//         ),
//       ],
//     );
//   }
// }

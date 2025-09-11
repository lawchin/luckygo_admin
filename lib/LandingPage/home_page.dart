import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ← add this
import 'package:flutter/material.dart';
import 'package:luckygo_admin/active_deposit.dart';
import 'package:luckygo_admin/geo_fencing/geo_fencing_page.dart';
import 'package:luckygo_admin/global.dart';
import 'package:luckygo_admin/help_center/customer_service.dart';
import 'package:luckygo_admin/login_register/login_page.dart';
import 'package:luckygo_admin/new_driver/new_driver.dart';
import 'package:luckygo_admin/pricing/price_change_by.dart';
import 'package:luckygo_admin/pricing/pricing.dart';
import 'package:luckygo_admin/sos/sos_victim.dart';

String getFormattedDate() {
  final now = DateTime.now();
  final day = now.day.toString().padLeft(2, '0');
  final month = now.month.toString().padLeft(2, '0');
  final year = now.year.toString().substring(2, 4);

  int hour = now.hour;
  final minute = now.minute.toString().padLeft(2, '0');
  final second = now.second.toString().padLeft(2, '0');

  final period = hour >= 12 ? 'PM' : 'AM';
  hour = hour % 12;
  if (hour == 0) hour = 12; // 12 AM or 12 PM

  final hourStr = hour.toString().padLeft(2, '0');

  return '$day$month$year $hourStr$minute$second$period';
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
appBar: AppBar(
  title: Builder(
    builder: (context) {
      // Derive phone digits from the signed-in email
      final user = FirebaseAuth.instance.currentUser;
      final phoneDigits = (user?.email ?? '')
          .split('@')
          .first
          .replaceAll(RegExp(r'[^0-9]'), '');

      final canQuery =
          negara.isNotEmpty && negeri.isNotEmpty && phoneDigits.isNotEmpty;

      if (!canQuery) {
        // Fallback if we can't query yet
        return const Text('Welcome Admin');
      }

      final docRef = FirebaseFirestore.instance
          .collection(negara)
          .doc(negeri)
          .collection('admin_account')
          .doc(phoneDigits);

      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasData && snap.data!.exists) {
            final data = snap.data!.data();
            final n = (data?['name'] as String?)?.trim();
            if (n != null && n.isNotEmpty) fullname = n;
          }
          return Text('Welcome${fullname.isNotEmpty ? ' $fullname' : ''}');
        },
      );
    },
  ),
  actions: [
    // 3-lines (hamburger) icon to open the *end* drawer (right side)
    Builder(
      builder: (ctx) => IconButton(
        icon: const Icon(Icons.menu),
        tooltip: 'Menu',
        onPressed: () => Scaffold.of(ctx).openEndDrawer(),
      ),
    ),
  ],
),

      // ← end drawer added here
      endDrawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                child: Text(
                  'LuckyGo Admin',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
ListTile(
  leading: const Icon(Icons.logout),
  title: const Text('Logout'),
  onTap: () async {
    final rootNav = Navigator.of(context, rootNavigator: true);

    // Close the endDrawer first
    Navigator.of(context).pop();

    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign out failed: $e')),
      );
      return;
    }

    // If you have AuthGate as MaterialApp.home, stopping here is enough.
    // If not using AuthGate, also navigate to LoginPage:
    if (context.mounted) {
      rootNav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    }
  },
),
            ],
          ),
        ),
      ),

      body: Center(
        child: Column(
          children: [
            Stack(// Active deposit
              children: [
                SizedBox(
                  width: 260,
                  child: ElevatedButton(
                    child: const Text('Active Deposits'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ActiveDeposit(),
                        ),
                      );
                    },
                  ),
                ),
                Positioned( // NUMBERING
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: StreamBuilder<int>(
                    stream: FirebaseFirestore.instance
                        .collection(negara)
                        .doc(negeri)
                        .collection('information')
                        .doc('banking')
                        .collection('deposit_data')
                        .where('deposit_needed_process', isEqualTo: true)
                        .snapshots()
                        .map((s) => s.size),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting || snapshot.hasError) {
                        return const SizedBox.shrink(); // hide while loading/error
                      }

                      final count = snapshot.data ?? 0;
                      if (count == 0) return const SizedBox.shrink(); // hide when zero

                      return const SizedBox(
                        width: 40,
                        child: Center(
                          child: Text(
                            '•', // you can keep your count text here if preferred
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            SizedBox(// Geo Fencing
              width: 260,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GeoFencingPage(),
                    ),
                  );
                },
                child: const Text('Geo Fencing'),
              ),
            ),

            Stack(// Customer service
              children: [
                SizedBox(
                  width: 260,
                  child: ElevatedButton(
                    child: const Text('Customer Service'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CustomerService(),
                        ),
                      );
                    },
                  ),
                ),
                Positioned( // NUMBERING
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: StreamBuilder<int>(
                    stream: FirebaseFirestore.instance
                        .collection(negara)
                        .doc(negeri)
                        .collection('help_center')
                        .doc('customer_service')
                        .collection('service_data')
                        .where('admin_seen', isEqualTo: false)
                        .snapshots()
                        .map((s) => s.size),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting || snapshot.hasError) {
                        return const SizedBox.shrink(); // hide while loading/error
                      }

                      final count = snapshot.data ?? 0;
                      if (count == 0) return const SizedBox.shrink(); // hide when zero

                      return SizedBox(
                        width: 40,
                        child: Center(
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            Stack(// New driver
              children: [
                SizedBox(
                  width: 260,
                  child: ElevatedButton(
                    child: const Text('New Driver'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NewDriver(),
                        ),
                      );
                    },
                  ),
                ),
                Positioned( // NUMBERING
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: StreamBuilder<int>(
                    stream: FirebaseFirestore.instance
                        .collection(negara)
                        .doc(negeri)
                        .collection('driver_account')
                        .where('registration_approved', isEqualTo: false)
                        .where('form2_completed', isEqualTo: true)
                        .snapshots()
                        .map((s) => s.size),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting || snapshot.hasError) {
                        return const SizedBox.shrink(); // hide while loading/error
                      }

                      final count = snapshot.data ?? 0;
                      if (count == 0) return const SizedBox.shrink(); // hide when zero

                      return SizedBox(
                        width: 40,
                        child: Center(
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            Stack(// SOS
              children: [
                SizedBox(
                  width: 260,
                  child: ElevatedButton(
                    child: const Text('SOS'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SosVictim(),
                        ),
                      );
                    },
                  ),
                ),
                Positioned( // NUMBERING
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: StreamBuilder<int>(
                    stream: FirebaseFirestore.instance
                        .collection(negara)
                        .doc(negeri)
                        .collection('help_center')
                        .doc('SOS')
                        .collection('sos_data')
                        .where('sos_solved', isEqualTo: false)
                        .snapshots()
                        .map((s) => s.size),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting || snapshot.hasError) {
                        return const SizedBox.shrink(); // hide while loading/error
                      }

                      final count = snapshot.data ?? 0;
                      if (count == 0) return const SizedBox.shrink(); // hide when zero

                      return SizedBox(
                        width: 40,
                        child: Center(
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            SizedBox(// pricing
              width: 260,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const Pricing(),
                    ),
                  );
                },
                child: const Text('Pricing'),
              ),
            ),

            SizedBox(// price update by
              width: 260,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PriceChangeBy(),
                    ),
                  );
                },
                child: const Text('Price update by'),
              ),
            ),


          ],
        ),
      ),
    );
  }
}

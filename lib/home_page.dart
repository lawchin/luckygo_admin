
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:luckygo_admin/active_deposit.dart';
import 'package:luckygo_admin/geo_fencing/geo_fencing_page.dart';
import 'package:luckygo_admin/global.dart';
import 'package:luckygo_admin/help_center/customer_service.dart';
import 'package:luckygo_admin/new_driver/new_driver.dart';

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
        title: const Text('Home Page'),
      ),
      body: Center(
        child: Column(
          children: [

            Stack(// Active deposit
              children: [
                SizedBox(
                  width:260,
                  child: ElevatedButton(
                    child: Text(
                      'Active Deposits',
                      
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ActiveDeposit(),
                        ),
                      );
                    }
                  ),
                ),
              Positioned(// NUMBERING
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
                    .map((snapshot) => snapshot.size),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        width: 40,
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }
                    if (snapshot.hasError) {
                      return const SizedBox(
                        width: 40,
                        child: Center(child: Icon(Icons.error, color: Colors.red)),
                      );
                    }
                    return Container(
                      width: 40,
                      alignment: Alignment.center,
                      child: Text(
                        '${snapshot.data ?? 0}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
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
                  width:260,
                  child: ElevatedButton(
                    child: Text(
                      'Customer Service',
                      
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CustomerService(),
                        ),
                      );
                    }
                  ),
                ),
              Positioned(// NUMBERING
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
                    .map((snapshot) => snapshot.size),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        width: 40,
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }
                    if (snapshot.hasError) {
                      return const SizedBox(
                        width: 40,
                        child: Center(child: Icon(Icons.error, color: Colors.red)),
                      );
                    }
                    return Container(
                      width: 40,
                      alignment: Alignment.center,
                      child: Text(
                        '${snapshot.data ?? 0}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
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
                  width:260,
                  child: ElevatedButton(
                    child: Text(
                      'New Driver',
                      
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NewDriver(),
                        ),
                      );
                    }
                  ),
                ),
              Positioned(// NUMBERING
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
                    .map((snapshot) => snapshot.size),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        width: 40,
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }
                    if (snapshot.hasError) {
                      return const SizedBox(
                        width: 40,
                        child: Center(child: Icon(Icons.error, color: Colors.red)),
                      );
                    }
                    return Container(
                      width: 40,
                      alignment: Alignment.center,
                      child: Text(
                        '${snapshot.data ?? 0}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          
          
          
          
          ],
        ),
      ),
    );
  }
}

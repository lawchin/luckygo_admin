
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:luckygo_admin/active_deposit.dart';
import 'package:luckygo_admin/geo_fencing/geo_fencing_page.dart';
import 'package:luckygo_admin/global.dart';


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

            Stack(
              children: [
                SizedBox(
                  width:200,
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
              Positioned(
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




            SizedBox(
              width: 200,
              child: ElevatedButton(// Geo Fencing
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
          ],
        ),
      ),
    );
  }
}

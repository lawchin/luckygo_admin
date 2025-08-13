
import 'package:flutter/material.dart';
import 'package:luckygo_admin/LandingPage/create_geofencing.dart';
import 'package:luckygo_admin/LandingPage/set_map_viewport.dart';


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
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SetMapViewport(),
                  ),
                );
              },
              child: const Text('Google Maps'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateGeoFencing(autoTarap: true),
                  ),
                );
              },
              child: const Text('Tarap'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateGeoFencing(autoKKIA: true),
                  ),
                );
              },
              child: const Text('KKIA'),
            ),





            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateGeoFencing(autoKionsom: true),
                  ),
                );
              },
              child: const Text('Kionsom House'),
            ),







          ],
        ),
      ),
    );
  }
}

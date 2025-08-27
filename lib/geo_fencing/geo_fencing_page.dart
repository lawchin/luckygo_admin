import 'package:flutter/material.dart';
import 'package:luckygo_admin/geo_fencing/create_geofencing.dart';
import 'package:luckygo_admin/geo_fencing/set_map_viewport.dart';


class GeoFencingPage extends StatelessWidget {
  const GeoFencingPage({super.key});






  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geo Fencing'),
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
                    builder: (context) => const CreateGeoFencing(autoAdrian: true),
                  ),
                );
              },
              child: const Text('Rumah Adrian'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreateGeoFencing(autoLaw: true),
                  ),
                );
              },
              child: const Text('Rumah Law'),
            ),
          ],
        ),
      ),
    );
  }
}

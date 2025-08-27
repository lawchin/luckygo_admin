import 'package:google_maps_flutter/google_maps_flutter.dart';

class GeoFencingHelper {
  
  final GoogleMapController mapController;

  GeoFencingHelper(this.mapController);

  Future<void> _goToExactView({
    required double lat,
    required double lng,
    required double zoom,
    required double bearing,
    required double tilt,
  }) async {
    final cam = CameraPosition(
      target: LatLng(lat, lng),
      zoom: zoom,
      tilt: tilt,
      bearing: bearing,
    );
    await mapController.animateCamera(
      CameraUpdate.newCameraPosition(cam),
    );
  }

  // Future<void> zoomToKKIA() async {
  //   await _goToExactView(
  //     lat: 5.92374,
  //     lng: 116.05175,
  //     zoom: 16.37,
  //     bearing: 248.2,
  //     tilt: 0.0,
  //   );
  // }

  // Future<void> zoomToTarap() async {
  //   await _goToExactView(
  //     lat: 5.98181,
  //     lng: 116.12923,
  //     zoom: 19.46,
  //     bearing: 295.0,
  //     tilt: 0.0,
  //   );
  // }

  // Future<void> zoomKionsomHouse() async {
  //   await _goToExactView(
  //     lat: 5.97383,
  //     lng: 116.20366,
  //     zoom: 19.95,
  //     bearing: 161.7,
  //     tilt: 0.0,
  //   );
  // }
}

// ignore_for_file: prefer_final_fields

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class SetMapViewport extends StatefulWidget {
  const SetMapViewport({super.key});

  @override
  State<SetMapViewport> createState() => _SetMapViewportState();
}

class _SetMapViewportState extends State<SetMapViewport> {
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();

  // Live camera (updated by onCameraMove). Placeholder; we jump to GPS on start.
  CameraPosition _camera = CameraPosition(
    target: LatLng(3.1390, 101.6869),
    zoom: 12,
    tilt: 0,
    bearing: 0,
  );

  StreamSubscription<Position>? _posSub;
  LatLng? _myLatLng;
  bool _myLocationEnabled = false;


  static Set<Marker> _markers = {
    Marker(
      markerId: MarkerId('kkia'),
      position: LatLng(5.9372, 116.0515),
      infoWindow: InfoWindow(title: 'KKIA'),
    ),
  };

  // gates to ensure we jump to user once (when both map + GPS are ready)
  bool _mapReady = false;
  bool _centeredOnUserOnce = false;

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
    _listenLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _ensureLocationPermission() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      setState(() => _myLocationEnabled = false);
      return;
    }
    setState(() => _myLocationEnabled = true);
  }

  void _listenLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;

    _posSub = Geolocator.getPositionStream().listen((pos) async {
      _myLatLng = LatLng(pos.latitude, pos.longitude);
      // ignore: avoid_print
      print('Location: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}');
      if (mounted) setState(() {});
      await _maybeCenterOnUserOnce();
    });
  }

  // Jump once to user's current location (NO animation)
  Future<void> _maybeCenterOnUserOnce() async {
    if (_centeredOnUserOnce || !_mapReady || _myLatLng == null) return;
    _centeredOnUserOnce = true;

    final map = await _controller.future;
    final cam = CameraPosition(
      target: _myLatLng!,
      zoom: 16,  // pick your default street-level zoom
      tilt: 0,
      bearing: 0,
    );
    await map.moveCamera(CameraUpdate.newCameraPosition(cam)); // instant
    if (!mounted) return;
    setState(() => _camera = cam);
  }

  void _onMapCreated(GoogleMapController c) {
    if (!_controller.isCompleted) _controller.complete(c);
    _mapReady = true;
    _maybeCenterOnUserOnce();
  }

  void _onCameraMove(CameraPosition cam) {
    _camera = cam;
    // ignore: avoid_print
    print('Rotation: ${cam.bearing.toStringAsFixed(2)}°, '
        'Zoom: ${cam.zoom.toStringAsFixed(2)}, '
        'Target: ${cam.target.latitude.toStringAsFixed(5)}, ${cam.target.longitude.toStringAsFixed(5)}, '
        'Tilt: ${cam.tilt.toStringAsFixed(1)}°');
    if (mounted) setState(() {}); // update the HUD
  }

  Future<void> _goToExactView({
    required double lat,
    required double lng,
    required double zoom,
    required double bearing,
    required double tilt,
  }) async {
    final map = await _controller.future;
    final cam = CameraPosition(
      target: LatLng(lat, lng),
      zoom: zoom,
      tilt: tilt,
      bearing: bearing,
    );
    await map.animateCamera(CameraUpdate.newCameraPosition(cam)); // uses default platform animation
    if (!mounted) return;
    setState(() => _camera = cam); // keep HUD in sync
  }
 
  void _printCurrentView() {
    final data = '''
      Bearing: ${_camera.bearing.toStringAsFixed(1)}°
      Zoom: ${_camera.zoom.toStringAsFixed(2)}
      Tilt: ${_camera.tilt.toStringAsFixed(1)}°
      Center: ${_camera.target.latitude.toStringAsFixed(5)}, ${_camera.target.longitude.toStringAsFixed(5)}
      MyLoc: ${_myLatLng == null ? '—' : '${_myLatLng!.latitude.toStringAsFixed(5)}, ${_myLatLng!.longitude.toStringAsFixed(5)}'}
      ''';
    // ignore: avoid_print
    print(data);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('View data printed to console')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _camera,
            onMapCreated: _onMapCreated,
            onCameraMove: _onCameraMove,

            mapType: MapType.hybrid, // satellite + labels
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            myLocationEnabled: _myLocationEnabled,
            myLocationButtonEnabled: true,
            markers: _markers,
            compassEnabled: true,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
          ),

          // Back button
          Positioned(
            top: 40,
            left: 16,
            child: FloatingActionButton(
              heroTag: 'back',
              mini: true,
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Icon(Icons.arrow_back),
            ),
          ),
        
        ],
      ),

      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
   
          FloatingActionButton.extended(
            heroTag: 'printview',
            onPressed: _printCurrentView,
            icon: const Icon(Icons.print),
            label: const Text('Print view data'),
          ),
        ],
      ),
    );
  }
}

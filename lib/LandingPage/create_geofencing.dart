// ignore_for_file: prefer_final_fields

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class CreateGeoFencing extends StatefulWidget {
  final bool autoTarap;
  final bool autoKKIA;
  final bool autoKionsom;
  const CreateGeoFencing({
    super.key,
    this.autoTarap = false,
    this.autoKKIA = false,
    this.autoKionsom = false,
  });

  @override
  State<CreateGeoFencing> createState() => _CreateGeoFencingState();
}

class _CreateGeoFencingState extends State<CreateGeoFencing> {
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();

  // Camera (we’ll use its target as the crosshair LatLng)
  CameraPosition _camera = const CameraPosition(
    target: LatLng(3.1390, 101.6869), // placeholder; overwritten if auto flag set
    zoom: 12,
    tilt: 0,
    bearing: 0,
  );

  // GPS
  StreamSubscription<Position>? _posSub;
  LatLng? _myLatLng;
  bool _myLocationEnabled = false;

  // Flow control
  bool _mapReady = false;
  bool _centeredOnUserOnce = false;

  // ------ geofence drawing state ------
  final List<LatLng> _fencePts = [];
  Set<Marker> _markers = {};
  Set<Polygon> _polygons = {};
  Set<Polyline> _polylines = {};
  // ------------------------------------

  bool get _wantsAuto => widget.autoTarap || widget.autoKKIA || widget.autoKionsom;

  // Preset views
  static const _tarap = CameraPosition(
    target: LatLng(5.98181, 116.12923),
    zoom: 19.46,
    tilt: 0,
    bearing: 295.0,
  );
  static const _kkia = CameraPosition(
    target: LatLng(5.92374, 116.05175),
    zoom: 16.37,
    tilt: 0,
    bearing: 248.2,
  );
  static const _kionsom = CameraPosition(
    target: LatLng(5.97383, 116.20366),
    zoom: 19.95,
    tilt: 0,
    bearing: 161.7,
  );

  // -------- Edit mode (crosshair at screen center) --------
  int? _editIdx;                // which point is being edited
  LatLng? _editOriginal;        // original to restore on cancel
  LatLng? _editTemp;            // live candidate = camera center while editing
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lngCtrl = TextEditingController();
  // --------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
    _listenLocation();
    _presetCameraIfAny();
  }

  void _presetCameraIfAny() {
    if (!_wantsAuto) return;
    if (widget.autoTarap) {
      _camera = _tarap;
    } else if (widget.autoKKIA) {
      _camera = _kkia;
    } else if (widget.autoKionsom) {
      _camera = _kionsom;
    }
    _centeredOnUserOnce = true; // don’t recenter if auto preset is active
    setState(() {});
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _latCtrl.dispose();
    _lngCtrl.dispose();
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
      if (mounted) setState(() {});
      if (!_wantsAuto) await _maybeCenterOnUserOnce();
    });
  }

  // One-time jump to user's location (no animation)
  Future<void> _maybeCenterOnUserOnce() async {
    if (_centeredOnUserOnce || !_mapReady || _myLatLng == null) return;
    _centeredOnUserOnce = true;
    final map = await _controller.future;
    final cam = CameraPosition(target: _myLatLng!, zoom: 16, tilt: 0, bearing: 0);
    await map.moveCamera(CameraUpdate.newCameraPosition(cam));
    if (!mounted) return;
    setState(() => _camera = cam);
  }

  void _onMapCreated(GoogleMapController c) async {
    if (!_controller.isCompleted) _controller.complete(c);
    _mapReady = true;

    if (_wantsAuto) {
      final map = await _controller.future;
      await map.moveCamera(CameraUpdate.newCameraPosition(_camera));
    } else {
      await _maybeCenterOnUserOnce();
    }
  }

  // Always keep _camera updated. While editing, the crosshair value = _camera.target.
  void _onCameraMove(CameraPosition cam) {
    _camera = cam;

    if (_editIdx != null) {
      _editTemp = cam.target; // crosshair is center
      _latCtrl.text = _editTemp!.latitude.toStringAsFixed(6);
      _lngCtrl.text = _editTemp!.longitude.toStringAsFixed(6);
      _rebuildPreviewOnly(); // show preview with live edit point
    }

    if (mounted) setState(() {}); // reflect HUD/editor text immediately
  }

  // ---------- Geofence builder ----------
  void _addPoint(LatLng p) {
    _fencePts.add(p);
    _rebuildMarkersAndLines();
  }

  void _undoPoint() {
    if (_fencePts.isEmpty) return;
    if (_editIdx != null && _editIdx == _fencePts.length - 1) {
      _cancelEdit();
    }
    _fencePts.removeLast();
    _polygons.clear();
    _rebuildMarkersAndLines();
  }

  void _clearFence() {
    _fencePts.clear();
    _markers.clear();
    _polylines.clear();
    _polygons.clear();
    _exitEdit();
    setState(() {});
  }

  // Build markers (hide the one being edited) and preview polyline
  void _rebuildMarkersAndLines() {
    _markers = {
      for (int i = 0; i < _fencePts.length; i++)
        if (_editIdx != i) // hide edited marker
          Marker(
            markerId: MarkerId('pt_$i'),
            position: _fencePts[i],
            onTap: () => _enterEdit(i),
            infoWindow: InfoWindow(
              title: '#${i + 1}',
              snippet:
                  '${_fencePts[i].latitude.toStringAsFixed(5)}, ${_fencePts[i].longitude.toStringAsFixed(5)}',
            ),
          ),
    };

    _rebuildPreviewOnly();
    setState(() {});
  }

  // While editing: preview is all points with the editing one replaced by _editTemp (camera center)
  void _rebuildPreviewOnly() {
    final pts = <LatLng>[];
    for (int i = 0; i < _fencePts.length; i++) {
      if (_editIdx == i && _editTemp != null) {
        pts.add(_editTemp!);
      } else {
        pts.add(_fencePts[i]);
      }
    }

    if (pts.length >= 2) {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('fence_preview'),
          points: pts,
          width: 3,
          geodesic: true,
        ),
      };
    } else {
      _polylines.clear();
    }

    // Clear final polygon while editing or until user reconnects
    _polygons.clear();
  }

  void _connectFence() {
    if (_fencePts.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Need at least 3 points to create a polygon')),
      );
      return;
    }
    // If editing, apply first
    if (_editIdx != null) {
      _applyEdit();
    }
    _polygons = {
      Polygon(
        polygonId: const PolygonId('geofence'),
        points: List<LatLng>.from(_fencePts),
        strokeWidth: 3,
        strokeColor: Colors.red,
        fillColor: Colors.red.withOpacity(0.20),
        geodesic: true,
      ),
    };
    _polylines = {
      Polyline(
        polylineId: const PolylineId('fence_outline'),
        points: [..._fencePts, _fencePts.first],
        width: 3,
        geodesic: true,
      ),
    };
    setState(() {});
  }

  // ---------- Edit mode: crosshair in the center ----------
  void _enterEdit(int index) async {
    _editIdx = index;
    _editOriginal = _fencePts[index];

    // Seed editTemp = current camera center if close, else move camera to the point
    final map = await _controller.future;
    _editTemp = _fencePts[index];
    await map.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _editTemp!, zoom: _camera.zoom, tilt: _camera.tilt, bearing: _camera.bearing),
      ),
    );

    // init editor fields
    _latCtrl.text = _editTemp!.latitude.toStringAsFixed(6);
    _lngCtrl.text = _editTemp!.longitude.toStringAsFixed(6);

    _polygons.clear();
    _rebuildMarkersAndLines(); // hides the marker, shows preview with center as edit point
  }

  void _applyEdit() {
    if (_editIdx == null) return;

    // Prefer typed values if valid; else use camera center
    final typedLat = double.tryParse(_latCtrl.text.trim());
    final typedLng = double.tryParse(_lngCtrl.text.trim());
    LatLng newPos = _camera.target;
    if (typedLat != null &&
        typedLng != null &&
        typedLat >= -90 &&
        typedLat <= 90 &&
        typedLng >= -180 &&
        typedLng <= 180) {
      newPos = LatLng(typedLat, typedLng);
    }

    _fencePts[_editIdx!] = newPos;
    _exitEdit();
    _rebuildMarkersAndLines();
  }

  void _cancelEdit() {
    if (_editIdx == null) return;
    // restore original
    _fencePts[_editIdx!] = _editOriginal!;
    _exitEdit();
    _rebuildMarkersAndLines();
  }

  void _deleteSelected() {
    if (_editIdx == null) return;
    _fencePts.removeAt(_editIdx!);
    _exitEdit();
    _rebuildMarkersAndLines();
  }

  void _exitEdit() {
    _editIdx = null;
    _editOriginal = null;
    _editTemp = null;
    _latCtrl.clear();
    _lngCtrl.clear();
  }
  // -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final editing = _editIdx != null;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _camera,
            onMapCreated: _onMapCreated,
            onCameraMove: _onCameraMove,

            onTap: _addPoint, // tap to add vertices
            mapType: MapType.hybrid,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            myLocationEnabled: _myLocationEnabled,
            myLocationButtonEnabled: true,

            markers: _markers,
            polygons: _polygons,
            polylines: _polylines,

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

          // Point count HUD
          Positioned(
            top: 40,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Points: ${_fencePts.length}',
                  style: const TextStyle(color: Colors.white)),
            ),
          ),

          // -------- Crosshair at screen center (size 12, red) --------
          if (editing)
            const Center(
              child: IgnorePointer(
                ignoring: true, // let map gestures pass through
                child: Text(
                  '×',
                  style: TextStyle(
                    fontSize: 12, // as requested
                    color: Colors.red,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          // -------------------------------------------------------------

          // -------- Side editor (semi-transparent) for live updates ----
          if (editing)
            Positioned(
              right: 12,
              top: 100,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header row: title + close
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Editing point #${(_editIdx! + 1)}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: _cancelEdit,
                              tooltip: 'Cancel (restore original)',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Live readout from camera center (updates in onCameraMove)
                        Text(
                          'Lat: ${_latCtrl.text}   Lng: ${_lngCtrl.text}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 6),

                        // Text fields (can also type exact values)
                        Row(
                          children: [
                            Expanded(
                              child: _glassField(
                                controller: _latCtrl,
                                label: 'Latitude',
                                hint: '-90..90',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _glassField(
                                controller: _lngCtrl,
                                label: 'Longitude',
                                hint: '-180..180',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Action buttons
                        Row(
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(foregroundColor: Colors.white),
                              onPressed: _deleteSelected,
                              child: const Text('Delete'),
                            ),
                            const Spacer(),
                            TextButton(
                              style: TextButton.styleFrom(foregroundColor: Colors.white70),
                              onPressed: _cancelEdit,
                              child: const Text('X'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _applyEdit,
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // -------------------------------------------------------------
        ],
      ),

      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'connect',
            onPressed: _connectFence,
            icon: const Icon(Icons.link),
            label: const Text('Connect (Polygon)'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'delete_last',
            onPressed: _undoPoint,
            icon: const Icon(Icons.delete),
            label: const Text('Delete Last Marker'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'undo',
            onPressed: _undoPoint,
            icon: const Icon(Icons.undo),
            label: const Text('Undo point'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'clear',
            onPressed: _clearFence,
            icon: const Icon(Icons.clear_all),
            label: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  // Small helper for glassy-looking text fields
  Widget _glassField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        isDense: true,
        filled: true,
        fillColor: Colors.white.withOpacity(0.12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white70),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}





// // ignore_for_file: prefer_final_fields

// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:luckygo_admin/LandingPage/geofencing_helper.dart';

// class CreateGeoFencing extends StatefulWidget {
//   final bool autoTarap;
//   final bool autoKKIA;
//   final bool autoKionsom;
//   const CreateGeoFencing({
//     super.key,
//     this.autoTarap = false,
//     this.autoKKIA = false,
//     this.autoKionsom = false,
//   });

//   @override
//   State<CreateGeoFencing> createState() => _CreateGeoFencingState();
// }

// class _CreateGeoFencingState extends State<CreateGeoFencing> {
//   final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();

//   CameraPosition _camera = const CameraPosition(
//     target: LatLng(3.1390, 101.6869),
//     zoom: 12,
//     tilt: 0,
//     bearing: 0,
//   );

//   StreamSubscription<Position>? _posSub;
//   LatLng? _myLatLng;
//   bool _myLocationEnabled = false;
//   static const LatLng _kkiaMarker = LatLng(5.9372, 116.0515);
//   static Set<Marker> _markers = {
//     Marker(
//       markerId: MarkerId('kkia'),
//       position: _kkiaMarker,
//       infoWindow: InfoWindow(title: 'KKIA'),
//     ),
//   };

//   bool _mapReady = false;
//   bool _centeredOnUserOnce = false;
//   bool _didAutoZoom = false;
//   bool get _wantsAuto =>
//       widget.autoTarap || widget.autoKKIA || widget.autoKionsom;

//   @override
//   void initState() {
//     super.initState();
//     _ensureLocationPermission();
//     _listenLocation();
//     Geolocator.getLastKnownPosition().then((pos) async {
//   if (!mounted || pos == null || _wantsAuto) return;
//   _myLatLng = LatLng(pos.latitude, pos.longitude);
//   if (_mapReady) {
//     final map = await _controller.future;
//     final cam = CameraPosition(target: _myLatLng!, zoom: 16, tilt: 0, bearing: 0);
//     map.moveCamera(CameraUpdate.newCameraPosition(cam));
//     setState(() => _camera = cam);
//   }
// });
//   }

//   @override
//   void dispose() {
//     _posSub?.cancel();
//     super.dispose();
//   }

//   Future<void> _ensureLocationPermission() async {
//     var p = await Geolocator.checkPermission();
//     if (p == LocationPermission.denied) {
//       p = await Geolocator.requestPermission();
//     }
//     if (!mounted) return;
//     if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
//       setState(() => _myLocationEnabled = false);
//       return;
//     }
//     setState(() => _myLocationEnabled = true);
//   }

//   void _listenLocation() async {
//     final enabled = await Geolocator.isLocationServiceEnabled();
//     if (!enabled) return;

//     _posSub = Geolocator.getPositionStream().listen((pos) async {
//       _myLatLng = LatLng(pos.latitude, pos.longitude);
//       // ignore: avoid_print
//       print('Location: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}');
//       if (mounted) setState(() {});
//       // Only center to user if we are NOT doing auto-zoom
//       if (!_wantsAuto) await _maybeCenterOnUserOnce();
//     });
//   }

//   Future<void> _maybeCenterOnUserOnce() async {
//     if (_centeredOnUserOnce || !_mapReady || _myLatLng == null) return;
//     _centeredOnUserOnce = true;

//     final map = await _controller.future;
//     final cam = CameraPosition(
//       target: _myLatLng!,
//       zoom: 16,
//       tilt: 0,
//       bearing: 0,
//     );
//     await map.moveCamera(CameraUpdate.newCameraPosition(cam));
//     if (!mounted) return;
//     setState(() => _camera = cam);
//   }
//   late GeoFencingHelper _gfHelper;

//   void _onMapCreated(GoogleMapController c) {
//     if (!_controller.isCompleted) _controller.complete(c);
//     _gfHelper = GeoFencingHelper(c); // initialize helper
//     _mapReady = true;

//     if (_wantsAuto) {
//       _centeredOnUserOnce = true;
//       if (!_didAutoZoom) {
//         _didAutoZoom = true;
//         if (widget.autoTarap) {
//           _gfHelper.zoomToTarap();
//         } else if (widget.autoKKIA) {
//           _gfHelper.zoomToKKIA();
//         } else if (widget.autoKionsom) {
//           _gfHelper.zoomKionsomHouse();
//         }
//       }
//     } else {
//       _maybeCenterOnUserOnce();
//     }
//   }

//   void _onCameraMove(CameraPosition cam) {
//     _camera = cam;
//     // ignore: avoid_print
//     print('Rotation: ${cam.bearing.toStringAsFixed(2)}°, '
//         'Zoom: ${cam.zoom.toStringAsFixed(2)}, '
//         'Target: ${cam.target.latitude.toStringAsFixed(5)}, ${cam.target.longitude.toStringAsFixed(5)}, '
//         'Tilt: ${cam.tilt.toStringAsFixed(1)}°');
//     if (mounted) setState(() {});
//   }


//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Stack(
//         children: [
//           GoogleMap(
//             initialCameraPosition: _camera,
//             onMapCreated: _onMapCreated,
//             onCameraMove: _onCameraMove,

//             mapType: MapType.hybrid, // satellite + labels
//             rotateGesturesEnabled: true,
//             tiltGesturesEnabled: true,
//             myLocationEnabled: _myLocationEnabled,
//             myLocationButtonEnabled: true,
//             markers: _markers,
//             compassEnabled: true,
//             zoomControlsEnabled: true,
//             mapToolbarEnabled: false,
//           ),

//           // Back button
//           Positioned(
//             top: 40,
//             left: 16,
//             child: FloatingActionButton(
//               heroTag: 'back',
//               mini: true,
//               onPressed: () => Navigator.of(context).maybePop(),
//               child: const Icon(Icons.arrow_back),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

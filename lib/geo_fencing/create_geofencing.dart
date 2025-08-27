// ignore_for_file: prefer_final_fields

import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Optional globals you said you use elsewhere:
// class Gv { static String negara = 'MY'; static String negeri = 'Sabah'; }

enum FenceLayer { red, green }

class CreateGeoFencing extends StatefulWidget {
  final bool autoTarap;
  final bool autoKKIA;
  final bool autoKionsom;
  final bool autoAdrian;
  final bool autoLaw;
  const CreateGeoFencing({
    super.key,
    this.autoTarap = false,
    this.autoKKIA = false,
    this.autoKionsom = false,
    this.autoAdrian = false,
    this.autoLaw = false,
  });

  @override
  State<CreateGeoFencing> createState() => _CreateGeoFencingState();
}

class _CreateGeoFencingState extends State<CreateGeoFencing> {
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();

  // Camera (crosshair reads camera.target while editing)
  CameraPosition _camera = const CameraPosition(
    target: LatLng(3.1390, 101.6869),
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

  // ------------ Two layers (RED = block, GREEN = allow) ------------
  FenceLayer _active = FenceLayer.red; // default interactive layer

  // Points (drafting)
  final List<LatLng> _redPts = [];
  final List<LatLng> _greenPts = [];

  // Markers (tap to edit) – only ACTIVE layer markers are tappable
  Set<Marker> _redMarkers = {};
  Set<Marker> _greenMarkers = {};

  // Final polygons
  Polygon? _redPolygon;   // red (may have holes if green fully inside)
  Polygon? _greenPolygon; // transparent fill; outline via _greenOutline

  // Previews (open polylines while drafting)
  Polyline? _redPreview;
  Polyline? _greenPreview;

  // Optional green outline (for visibility of allow island boundary)
  Polyline? _greenOutline;

  bool get _wantsAuto => widget.autoTarap 
  || widget.autoKKIA 
  || widget.autoKionsom 
  || widget.autoAdrian
  || widget.autoLaw
  ;


  static const _kkia = CameraPosition(
    target: LatLng(5.92374, 116.05175), zoom: 16.37, tilt: 0, bearing: 248.2,
  );
  static const _adrian = CameraPosition(
    target: LatLng(6.00930, 116.11345), zoom: 19.82, tilt: 0, bearing: 65.8,
  );
  static const _law = CameraPosition(
    target: LatLng(5.97402, 116.12329), zoom: 20.55, tilt: 0, bearing: 113.0,
  );

  // -------- Crosshair edit mode (layer-aware) --------
  FenceLayer? _editLayer;
  int? _editIdx;
  LatLng? _editTemp;
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lngCtrl = TextEditingController();
  // ---------------------------------------------------

  // ---------- Derived doc id from selected auto flag ----------
  String get _docId {
    if (widget.autoTarap) return 'tarap';
    if (widget.autoKKIA) return 'kkia';
    if (widget.autoKionsom) return 'kionsom';
    if (widget.autoAdrian) return 'adrian';
    return 'custom_${DateTime.now().millisecondsSinceEpoch}';
  }

  // ---------- Name (human readable) ----------
  String get _geoName {
    if (widget.autoTarap) return 'Tarap Block Zone';
    if (widget.autoKKIA) return 'KKIA Block Zone';
    if (widget.autoKionsom) return 'Kionsom Block Zone';
    if (widget.autoAdrian) return 'Rumah Adrian';
    if (widget.autoLaw) return 'Rumah Law';
    return 'Custom Block Zone';
  }

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
    _listenLocation();
    _presetCameraIfAny();
  }

  void _presetCameraIfAny() {
    if (!_wantsAuto) return;
    else if (widget.autoKKIA) _camera = _kkia;
    else if (widget.autoAdrian) _camera = _adrian;
    else if (widget.autoLaw) _camera = _law;
    _centeredOnUserOnce = true;
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

  void _onCameraMove(CameraPosition cam) {
    _camera = cam;

    // Live crosshair update while editing
    if (_editLayer != null && _editIdx != null) {
      _editTemp = cam.target;
      _latCtrl.text = _editTemp!.latitude.toStringAsFixed(6);
      _lngCtrl.text = _editTemp!.longitude.toStringAsFixed(6);
      _rebuildPreviewOnly(); // update only previews
    }
    if (mounted) setState(() {});
  }

  // ---------------- TAP to add (ACTIVE layer only) ----------------
  void _onMapTap(LatLng p) {
    if (_active == FenceLayer.red) {
      _redPts.add(p);
      _rebuildRed();
    } else {
      _greenPts.add(p);
      _rebuildGreen();
    }
  }

  // ----------------- Rebuild helpers (per layer) ------------------
  Marker _buildMarker({
    required FenceLayer layer,
    required int index,
    required LatLng pos,
  }) {
    final hue = layer == FenceLayer.red
        ? BitmapDescriptor.hueRed
        : BitmapDescriptor.hueGreen;

    // Only ACTIVE layer markers are tappable (others inert)
    final bool tappable = (layer == _active);

    return Marker(
      markerId: MarkerId('${layer.name}_$index'),
      position: pos,
      icon: BitmapDescriptor.defaultMarkerWithHue(hue),
      onTap: tappable ? () => _enterEdit(layer, index) : null,
      infoWindow: tappable
          ? InfoWindow(
              title: '#${index + 1} (${layer.name})',
              snippet: '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
            )
          : InfoWindow.noText,
    );
  }

  void _rebuildRed() {
    _redMarkers = {
      for (int i = 0; i < _redPts.length; i++)
        if (!(_editLayer == FenceLayer.red && _editIdx == i))
          _buildMarker(layer: FenceLayer.red, index: i, pos: _redPts[i]),
    };

    final pts = _previewPointsFor(FenceLayer.red);
    _redPreview = (pts.length >= 2)
        ? Polyline(
            polylineId: const PolylineId('red_preview'),
            points: pts, width: 3, color: Colors.red, geodesic: true)
        : null;

    _updateDonutPolygon(); // sync donut when red changes
    setState(() {});
  }

  void _rebuildGreen() {
    _greenMarkers = {
      for (int i = 0; i < _greenPts.length; i++)
        if (!(_editLayer == FenceLayer.green && _editIdx == i))
          _buildMarker(layer: FenceLayer.green, index: i, pos: _greenPts[i]),
    };

    final pts = _previewPointsFor(FenceLayer.green);
    _greenPreview = (pts.length >= 2)
        ? Polyline(
            polylineId: const PolylineId('green_preview'),
            points: pts, width: 3, color: Colors.green, geodesic: true)
        : null;

    _updateDonutPolygon(); // sync donut when green changes
    setState(() {});
  }

  List<LatLng> _previewPointsFor(FenceLayer layer) {
    final src = layer == FenceLayer.red ? _redPts : _greenPts;
    final pts = <LatLng>[];
    for (int i = 0; i < src.length; i++) {
      if (_editLayer == layer && _editIdx == i && _editTemp != null) {
        pts.add(_editTemp!);
      } else {
        pts.add(src[i]);
      }
    }
    return pts;
  }

  void _rebuildPreviewOnly() {
    final redPts = _previewPointsFor(FenceLayer.red);
    _redPreview = (redPts.length >= 2)
        ? Polyline(
            polylineId: const PolylineId('red_preview'),
            points: redPts, width: 3, color: Colors.red, geodesic: true)
        : null;

    final greenPts = _previewPointsFor(FenceLayer.green);
    _greenPreview = (greenPts.length >= 2)
        ? Polyline(
            polylineId: const PolylineId('green_preview'),
            points: greenPts, width: 3, color: Colors.green, geodesic: true)
        : null;
  }

  // ----------------- Active layer actions -----------------
  void _undoLast() {
    if (_active == FenceLayer.red) {
      if (_redPts.isEmpty) return;
      if (_editLayer == FenceLayer.red && _editIdx == _redPts.length - 1) _cancelEdit();
      _redPts.removeLast();
      _rebuildRed();
    } else {
      if (_greenPts.isEmpty) return;
      if (_editLayer == FenceLayer.green && _editIdx == _greenPts.length - 1) _cancelEdit();
      _greenPts.removeLast();
      _rebuildGreen();
    }
  }

  void _clearActive() {
    if (_active == FenceLayer.red) {
      _redPts.clear();
      _redMarkers.clear();
      _redPreview = null;
      _redPolygon = null;
      if (_editLayer == FenceLayer.red) _exitEdit();
      _updateDonutPolygon();
      setState(() {});
    } else {
      _greenPts.clear();
      _greenMarkers.clear();
      _greenPreview = null;
      _greenPolygon = null;
      _greenOutline = null;
      if (_editLayer == FenceLayer.green) _exitEdit();
      _updateDonutPolygon();
      setState(() {});
    }
  }

  void _connectActive() {
    final pts = _active == FenceLayer.red ? _redPts : _greenPts;
    if (pts.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add at least 3 ${_active == FenceLayer.red ? 'RED' : 'GREEN'} points')),
      );
      return;
    }
    if (_editLayer == _active) _applyEdit(); // finalize current edit first

    if (_active == FenceLayer.red) {
      _redPolygon = Polygon(
        polygonId: const PolygonId('red_polygon'),
        points: List<LatLng>.from(_redPts),
        strokeWidth: 3,
        strokeColor: Colors.red,
        fillColor: Colors.red.withOpacity(0.20),
        geodesic: true,
      );
      _redPreview = null;
    } else {
      _greenPolygon = Polygon(
        polygonId: const PolygonId('green_polygon'),
        points: List<LatLng>.from(_greenPts),
        strokeWidth: 3,
        strokeColor: Colors.green,
        fillColor: Colors.transparent, // acts as a hole (visual via red.holes)
        geodesic: true,
      );
      _greenPreview = null;

      _greenOutline = Polyline(
        polylineId: const PolylineId('green_outline'),
        points: [..._greenPts, _greenPts.first],
        width: 3,
        color: Colors.green,
        geodesic: true,
      );
    }

    // Warn if green is not fully inside red (hole won't be applied)
    if (_active == FenceLayer.green && _redPts.length >= 3 && _greenPts.length >= 3) {
      final inside = _isRingInside(_redPts, _greenPts);
      if (!inside) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Green must be fully inside red to cut a hole. Showing outline only.'),
          ),
        );
      }
    }

    _updateDonutPolygon();
    setState(() {});
  }

  // ----------------- Donut builder (red with hole if possible) -----------------
  void _updateDonutPolygon() {
    final hasRed = _redPts.length >= 3;
    final hasGreen = _greenPts.length >= 3;

    // default: no hole
    List<List<LatLng>> holes = const [];

    // only apply hole if ALL green vertices are inside red
    if (hasRed && hasGreen && _isRingInside(_redPts, _greenPts)) {
      holes = [List<LatLng>.from(_greenPts)];
    }

    _redPolygon = hasRed
        ? Polygon(
            polygonId: const PolygonId('red_polygon'),
            points: List<LatLng>.from(_redPts),
            holes: holes,
            strokeWidth: 3,
            strokeColor: Colors.red,
            fillColor: Colors.red.withOpacity(0.20),
            geodesic: true,
          )
        : null;

    // Keep green polygon transparent + outline for visibility
    if (hasGreen) {
      _greenPolygon = Polygon(
        polygonId: const PolygonId('green_polygon'),
        points: List<LatLng>.from(_greenPts),
        strokeWidth: 3,
        strokeColor: Colors.green,
        fillColor: Colors.transparent,
        geodesic: true,
      );
      _greenOutline = Polyline(
        polylineId: const PolylineId('green_outline'),
        points: [..._greenPts, _greenPts.first],
        width: 3,
        color: Colors.green,
        geodesic: true,
      );
    } else {
      _greenPolygon = null;
      _greenOutline = null;
    }
  }

  // ----------------- Point-in-polygon + containment check -----------------
  bool _pointInPolygon(LatLng p, List<LatLng> poly) {
    bool inside = false;
    final x = p.longitude, y = p.latitude;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].longitude, yi = poly[i].latitude;
      final xj = poly[j].longitude, yj = poly[j].latitude;
      final intersect = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  bool _isRingInside(List<LatLng> outer, List<LatLng> inner) {
    // Simple check: every inner vertex must be inside the outer
    for (final p in inner) {
      if (!_pointInPolygon(p, outer)) return false;
    }
    return true;
  }

  // ----------------- Edit mode (crosshair) -----------------
  Future<void> _enterEdit(FenceLayer layer, int index) async {
    _editLayer = layer;
    _editIdx = index;

    final src = layer == FenceLayer.red ? _redPts : _greenPts;
    _editTemp = src[index];

    // Move camera to that point; crosshair is fixed center
    final map = await _controller.future;
    await map.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _editTemp!, zoom: _camera.zoom, tilt: _camera.tilt, bearing: _camera.bearing),
      ),
    );

    _latCtrl.text = _editTemp!.latitude.toStringAsFixed(6);
    _lngCtrl.text = _editTemp!.longitude.toStringAsFixed(6);

    // Hide the tapped marker (rebuild that layer only)
    if (layer == FenceLayer.red) _rebuildRed(); else _rebuildGreen();
  }

  void _applyEdit() {
    if (_editLayer == null || _editIdx == null) return;

    // Prefer typed values if valid; else use camera center
    final typedLat = double.tryParse(_latCtrl.text.trim());
    final typedLng = double.tryParse(_lngCtrl.text.trim());
    LatLng newPos = _camera.target;
    if (typedLat != null &&
        typedLng != null &&
        typedLat >= -90 && typedLat <= 90 &&
        typedLng >= -180 && typedLng <= 180) {
      newPos = LatLng(typedLat, typedLng);
    }

    if (_editLayer == FenceLayer.red) {
      _redPts[_editIdx!] = newPos;
      _exitEdit();
      _rebuildRed();
    } else {
      _greenPts[_editIdx!] = newPos;
      _exitEdit();
      _rebuildGreen();
    }
    _updateDonutPolygon();
  }

  void _cancelEdit() {
    if (_editLayer == null) return;
    _exitEdit();
    if (_editLayer == FenceLayer.red) _rebuildRed(); else _rebuildGreen();
  }

  void _deleteSelected() {
    if (_editLayer == null || _editIdx == null) return;
    if (_editLayer == FenceLayer.red) {
      _redPts.removeAt(_editIdx!);
      _exitEdit();
      _rebuildRed();
    } else {
      _greenPts.removeAt(_editIdx!);
      _exitEdit();
      _rebuildGreen();
    }
    _updateDonutPolygon();
  }

  void _exitEdit() {
    _editLayer = null;
    _editIdx = null;
    _editTemp = null;
    _latCtrl.clear();
    _lngCtrl.clear();
  }

  // ----------------- Firestore publish -----------------

Future<void> _publishToFirestore() async {
  void log(String msg) => debugPrint('[GEOFENCE PUBLISH] $msg');
  void toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // 0) quick input validation
  if (_redPts.length < 3) {
    toast('Need at least 3 RED points to publish');
    log('abort: red points < 3');
    return;
  }

  // helpers
  List<GeoPoint> toGeoRing(List<LatLng> ring) =>
      ring.map((p) => GeoPoint(p.latitude, p.longitude)).toList();

  String ringToStr(List<LatLng> ring) =>
      ring.map((p) => '(${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)})').join(', ');

  // 1) environment info
  try {
    final app = Firebase.apps.isNotEmpty ? Firebase.app() : null;
    if (app == null) {
      toast('Firebase not initialized (Firebase.app() is null)');
      log('error: Firebase.app() is null. Did you call Firebase.initializeApp()?');
      return;
    }
    final opts = app.options;
    log('firebase app: ${app.name}');
    log('projectId  : ${opts.projectId}');
    log('apiKey     : ${opts.apiKey?.substring(0, 6)}******');
    log('appId      : ${opts.appId}');
  } catch (e, st) {
    log('warning: failed to read Firebase.app() options: $e\n$st');
  }

  // 2) best-effort network reachability (non-fatal)
  try {
    final result = await InternetAddress.lookup('firestore.googleapis.com').timeout(const Duration(seconds: 3));
    log('dns check: ${result.isNotEmpty ? 'ok' : 'empty'}');
  } catch (_) {
    log('dns check failed (offline or DNS issue). continuing anyway…');
  }

  // 3) compute bbox
  final minLat = _redPts.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
  final maxLat = _redPts.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
  final minLng = _redPts.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
  final maxLng = _redPts.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

  // 4) build Firestore-friendly shapes (no nested arrays)
  final outerGeo = toGeoRing(_redPts);

  final bool greenInside = (_greenPts.length >= 3 && _isRingInside(_redPts, _greenPts));
  final List<Map<String, dynamic>> holesWrapped = greenInside
      ? [
          {"ring": toGeoRing(_greenPts)}
        ]
      : <Map<String, dynamic>>[];

  // cheap hash of outer for dedupe/debug
  final outerHash = _redPts
      .map((p) => '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}')
      .join('|')
      .hashCode;

  final data = {
    "schema": {"version": 1}, // for future migrations
    "name": _geoName,
    "active": true,
    "type": "block",
    // ✅ Firestore-friendly
    "outer": outerGeo,          // List<GeoPoint>
    "holes": holesWrapped,      // List<Map<String, dynamic>> where ring: List<GeoPoint>
    "bbox": {
      "minLat": minLat,
      "minLng": minLng,
      "maxLat": maxLat,
      "maxLng": maxLng,
    },
    "updatedAt": DateTime.now().millisecondsSinceEpoch,
    "hash": outerHash,
  };

  // 5) target path
  final negara = 'Malaysia';
  final negeri = 'Sabah';
  final docId = _docId;

  final docRef = FirebaseFirestore.instance
      .collection(negara)
      .doc(negeri)
      .collection('information')
      .doc('geo_fencing')
      .collection('all_geo_fencing')
      .doc(docId);

  log('target path: /$negara/$negeri/information/$docId');
  log('outer ring : ${ringToStr(_redPts)}');
  if (_greenPts.isNotEmpty) {
    log('green ring : ${ringToStr(_greenPts)} (fully-inside=$greenInside)');
  }
  log('bbox       : [($minLat,$minLng) → ($maxLat,$maxLng)]');

  // 6) quick read-probe (non-fatal)
  try {
    log('read-probe: ${docRef.path}');
    final snap = await docRef.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 8));
    log('read-probe ok: exists=${snap.exists}');
  } on FirebaseException catch (e, st) {
    log('read-probe FirebaseException: code=${e.code}, message=${e.message}');
    toast('Firestore read failed (${e.code}). Check rules/path.');
    log('stack:\n$st');
  } catch (e, st) {
    log('read-probe generic error: $e\n$st');
  }

  // 7) write (with timeout & detailed errors)
  try {
    log('writing… (merge=true)');
    await docRef.set(data, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
    toast('Published: $docId');
    log('write ok ✅');
  } on FirebaseException catch (e, st) {
    toast('Publish failed: ${e.code}');
    log('write FirebaseException ❌ code=${e.code}');
    log('message=${e.message}');
    if (e.plugin.isNotEmpty) log('plugin=${e.plugin}');
    log('stack:\n$st');

    switch (e.code) {
      case 'permission-denied':
        log('hint: update Firestore rules or confirm the path /$negara/$negeri/information has write access for this user/app.');
        break;
      case 'unavailable':
        log('hint: network/server issue. retry later or check connectivity.');
        break;
      case 'deadline-exceeded':
        log('hint: slow network. consider increasing timeout or checking internet stability.');
        break;
      case 'not-found':
        log('hint: parent docs auto-create on write; re-check collection/doc names.');
        break;
    }
  } on TimeoutException catch (e) {
    toast('Publish timed out');
    log('write timeout ❌: $e');
  } catch (e, st) {
    toast('Publish failed: $e');
    log('write generic error ❌: $e\n$st');
  }
}

  // ----------------- UI -----------------
  
  
  @override
  Widget build(BuildContext context) {
    final editing = _editLayer != null;

    final markers = <Marker>{..._redMarkers, ..._greenMarkers};
    final polygons = <Polygon>{
      if (_redPolygon != null) _redPolygon!,
      if (_greenPolygon != null) _greenPolygon!, // transparent fill
    };
    final polylines = <Polyline>{
      if (_redPreview != null) _redPreview!,
      if (_greenPreview != null) _greenPreview!,
      if (_greenOutline != null) _greenOutline!, // outline for allow island
    };

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _camera,
            onMapCreated: _onMapCreated,
            onCameraMove: _onCameraMove,
            onTap: _onMapTap, // add to ACTIVE layer only

            mapType: MapType.hybrid,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            myLocationEnabled: _myLocationEnabled,
            myLocationButtonEnabled: true,

            markers: markers,
            polygons: polygons,
            polylines: polylines,

            compassEnabled: true,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
          ),

          // Back
          Positioned(
            top: 40, left: 16,
            child: FloatingActionButton(
              heroTag: 'back',
              mini: true,
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Icon(Icons.arrow_back),
            ),
          ),

          // Layer toggles (top-right)
          Positioned(
            top: 40, right: 16,
            child: Row(
              children: [
                _layerChip(
                  color: Colors.red,
                  active: _active == FenceLayer.red,
                  label: 'Red',
                  onTap: () => setState(() {
                    _active = FenceLayer.red;
                    _rebuildRed(); _rebuildGreen(); // refresh tapability
                  }),
                ),
                const SizedBox(width: 8),
                _layerChip(
                  color: Colors.green,
                  active: _active == FenceLayer.green,
                  label: 'Green',
                  onTap: () => setState(() {
                    _active = FenceLayer.green;
                    _rebuildRed(); _rebuildGreen();
                  }),
                ),
              ],
            ),
          ),

          // Crosshair (edit mode)
          if (editing)
            const Center(
              child: IgnorePointer(
                ignoring: true,
                child: Text(
                  '×',
                  style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w900),
                ),
              ),
            ),

          // Editor panel (edit mode)
          if (editing)
            Positioned(
              right: 12, top: 120,
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Editing ${_editLayer == FenceLayer.red ? 'RED' : 'GREEN'} #${(_editIdx! + 1)}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: _cancelEdit,
                              tooltip: 'Cancel',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Lat: ${_latCtrl.text}   Lng: ${_lngCtrl.text}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: _glassField(controller: _latCtrl, label: 'Latitude', hint: '-90..90')),
                            const SizedBox(width: 8),
                            Expanded(child: _glassField(controller: _lngCtrl, label: 'Longitude', hint: '-180..180')),
                          ],
                        ),
                        const SizedBox(height: 10),
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
                            ElevatedButton(onPressed: _applyEdit, child: const Text('OK')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),

      // Active-layer tools + Publish
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'publish',
            onPressed: _publishToFirestore,
            icon: const Icon(Icons.cloud_upload),
            label: Text('Publish → ${_docId.toUpperCase()}'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'connect_active',
            onPressed: _connectActive,
            icon: const Icon(Icons.link),
            label: Text('Connect ${_active == FenceLayer.red ? 'RED' : 'GREEN'}'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'delete_last_active',
            onPressed: _undoLast,
            icon: const Icon(Icons.delete),
            label: Text('Delete Last (${_active == FenceLayer.red ? 'RED' : 'GREEN'})'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'clear_active',
            onPressed: _clearActive,
            icon: const Icon(Icons.clear_all),
            label: Text('Clear ${_active == FenceLayer.red ? 'RED' : 'GREEN'}'),
          ),
        ],
      ),
    );
  }

  // Tiny colored "chip" for layer toggle
  Widget _layerChip({
    required Color color,
    required bool active,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1.4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : color,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // Glassy text field
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

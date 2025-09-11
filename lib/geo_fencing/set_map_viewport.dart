// ignore_for_file: prefer_final_fields, unnecessary_string_interpolations

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:luckygo_admin/global.dart';
import 'package:luckygo_admin/LandingPage/home_page.dart';
import 'package:uuid/uuid.dart';

class SetMapViewport extends StatefulWidget {
  // === NEW: params accepted from GeoFencingPage ===
  final dynamic center; // "lat, lng" | [lat,lng] | {lat,lng}
  final double? zoom;
  final double? bearing;
  final double? tilt;
  final dynamic myloc; // same parsing rules as center
  final String? name;

  const SetMapViewport({
    super.key,
    this.center,
    this.zoom,
    this.bearing,
    this.tilt,
    this.myloc,
    this.name,
  });

  @override
  State<SetMapViewport> createState() => _SetMapViewportState();
}

class _SetMapViewportState extends State<SetMapViewport> {
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();

  // ====== Autocomplete state ======
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;
  final _uuid = const Uuid();
  String _sessionToken = "";
  List<_Suggestion> _suggestions = [];
  bool _isSearching = false;

  // === Places API keys copied from luckygo_passenger (tries key[0], then key[1] on API_KEY_INVALID) ===
  final List<String> _placesKeys = const [
    'AIzaSyBr2bdTwwE-x9PyHSArUbCgZ_BsDupqmfA',
    'AIzaSyDa5S3_IbRkjAJsH53VIXca0ZPLm9WcSHw',
  ];
  int _activePlacesKey = 0;

  // Default to Inanam, KK if nothing is passed
  static const LatLng _inanam = LatLng(6.0146, 116.1230);

  // NOTE: not const anymore; we may override from incoming params
  late CameraPosition _camera;

  StreamSubscription<Position>? _posSub;
  LatLng? _myLatLng;
  bool _myLocationEnabled = false;

  static Set<Marker> _markers = {
    const Marker(
      markerId: MarkerId('kkia'),
      position: LatLng(5.9372, 116.0515),
      infoWindow: InfoWindow(title: 'KKIA'),
    ),
  };

  bool _mapReady = false;
  bool _centeredOnUserOnce = false;

  // ---------------- Parsing helpers ----------------

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  LatLng? _toLatLng(dynamic v) {
    if (v == null) return null;

    if (v is String) {
      final parts = v.split(',');
      if (parts.length >= 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) return LatLng(lat, lng);
      }
      return null;
    }
    if (v is List && v.length >= 2) {
      final lat = _toDouble(v[0]);
      final lng = _toDouble(v[1]);
      if (lat != null && lng != null) return LatLng(lat, lng);
      return null;
    }
    if (v is Map) {
      final lat = _toDouble(v['lat'] ?? v['latitude']);
      final lng = _toDouble(v['lng'] ?? v['longitude']);
      if (lat != null && lng != null) return LatLng(lat, lng);
      return null;
    }
    return null;
  }

  // --------------------------------------------------

  @override
  void initState() {
    super.initState();

    // Initialize camera from incoming params (fallback to Inanam)
    final LatLng camTarget = _toLatLng(widget.center) ?? _inanam;
    final double camZoom = widget.zoom ?? 14.0;
    final double camBearing = widget.bearing ?? 0.0;
    final double camTilt = widget.tilt ?? 0.0;

    _camera = CameraPosition(
      target: camTarget,
      zoom: camZoom,
      tilt: camTilt,
      bearing: camBearing,
    );

    // Initialize "my location" if provided
    _myLatLng = _toLatLng(widget.myloc);

    _ensureLocationPermission();
    _listenLocation();

    _sessionToken = _uuid.v4();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _posSub?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
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
      zoom: 16,
      tilt: 0,
      bearing: 0,
    );
    await map.moveCamera(CameraUpdate.newCameraPosition(cam));
    if (!mounted) return;
    setState(() => _camera = cam);
  }

  void _onMapCreated(GoogleMapController c) async {
    if (!_controller.isCompleted) _controller.complete(c);
    _mapReady = true;

    // If no GPS yet, ensure we show the requested center (already in _camera)
    if (!_centeredOnUserOnce && _myLatLng == null) {
      final map = await _controller.future;
      await map.moveCamera(CameraUpdate.newCameraPosition(_camera));
    }

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
    await map.animateCamera(CameraUpdate.newCameraPosition(cam));
    if (!mounted) return;
    setState(() => _camera = cam);
  }

  void namedArea() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(widget.name == null || widget.name!.isEmpty
              ? 'Enter a name for your selected area'
              : 'Area: ${widget.name}'),
          content: TextField(
            controller: areaNameController,
            decoration: const InputDecoration(hintText: 'Area name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () async {
                await setupButton();
                if (mounted) Navigator.of(context).pop();
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Future<void> setupButton() async {
    await FirebaseFirestore.instance
        .collection(negara)
        .doc(negeri)
        .collection('information')
        .doc('geo_fencing')
        .collection('geo_fencing_button')
        .doc('${getFormattedDate()}(${areaNameController.text})')
        .set({
      'name': areaNameController.text,
      'bearing': _camera.bearing.toStringAsFixed(1),
      'zoom': _camera.zoom.toStringAsFixed(2),
      'tilt': _camera.tilt.toStringAsFixed(1),
      'center':
          '${_camera.target.latitude.toStringAsFixed(5)}, ${_camera.target.longitude.toStringAsFixed(5)}',
      'myloc': _myLatLng == null
          ? '—'
          : '${_myLatLng!.latitude.toStringAsFixed(5)}, ${_myLatLng!.longitude.toStringAsFixed(5)}',
    });

    final data = '''
      Bearing: ${_camera.bearing.toStringAsFixed(1)}°
      Zoom: ${_camera.zoom.toStringAsFixed(2)}
      Tilt: ${_camera.tilt.toStringAsFixed(1)}°
      Center: ${_camera.target.latitude.toStringAsFixed(5)}, ${_camera.target.longitude.toStringAsFixed(5)}
      MyLoc: ${_myLatLng == null ? '—' : '${_myLatLng!.latitude.toStringAsFixed(5)}, ${_myLatLng!.longitude.toStringAsFixed(5)}'}
      ''';
    // ignore: avoid_print
    print(data);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('View data printed to console')),
    );
  }

  // ====== Autocomplete logic ======
  void _onSearchChanged() {
    final text = _searchCtrl.text.trim();
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (text.isEmpty) {
        if (mounted) setState(() => _suggestions = []);
        return;
      }
      await _fetchAutocomplete(text);
    });
  }

  Map<String, String> _placesHeaders({String fieldMask = ''}) {
    return {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": _placesKeys[_activePlacesKey],
      if (fieldMask.isNotEmpty) "X-Goog-FieldMask": fieldMask,
    };
  }

  Future<http.Response> _placesPost(Uri uri, Map<String, dynamic> body, {String fieldMask = ''}) async {
    http.Response res = await http.post(uri, headers: _placesHeaders(fieldMask: fieldMask), body: jsonEncode(body));
    if (res.statusCode == 400 && res.body.contains('API_KEY_INVALID') && _activePlacesKey == 0) {
      _activePlacesKey = 1;
      res = await http.post(uri, headers: _placesHeaders(fieldMask: fieldMask), body: jsonEncode(body));
    }
    return res;
  }

  Future<http.Response> _placesGet(Uri uri, {String fieldMask = ''}) async {
    http.Response res = await http.get(uri, headers: _placesHeaders(fieldMask: fieldMask));
    if (res.statusCode == 400 && res.body.contains('API_KEY_INVALID') && _activePlacesKey == 0) {
      _activePlacesKey = 1;
      res = await http.get(uri, headers: _placesHeaders(fieldMask: fieldMask));
    }
    return res;
  }

  Future<void> _fetchAutocomplete(String query) async {
    setState(() => _isSearching = true);

    final biasLat = _camera.target.latitude;
    final biasLng = _camera.target.longitude;

    final uri = Uri.parse('https://places.googleapis.com/v1/places:autocomplete');
    final body = {
      "input": query,
      "sessionToken": _sessionToken,
      "locationBias": {
        "circle": {
          "center": {"latitude": biasLat, "longitude": biasLng},
          "radius": 30000.0
        }
      }
    };

    final res = await _placesPost(
      uri,
      body,
      fieldMask: "suggestions.placePrediction.placeId,suggestions.placePrediction.text",
    );

    if (!mounted) return;
    setState(() => _isSearching = false);

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (data["suggestions"] as List<dynamic>? ?? [])
          .map((s) => _Suggestion.fromJson(s))
          .toList();
      setState(() => _suggestions = list);
    } else {
      // ignore: avoid_print
      print('Autocomplete error: ${res.statusCode} ${res.body}');
      setState(() => _suggestions = []);
    }
  }

  Future<void> _onSuggestionTap(_Suggestion s) async {
    final placeId = s.placeId;
    final uri = Uri.parse('https://places.googleapis.com/v1/places/$placeId');

    final res = await _placesGet(
      uri,
      fieldMask: "id,displayName,location",
    );

    if (res.statusCode != 200) {
      // ignore: avoid_print
      print('Place details error: ${res.statusCode} ${res.body}');
      return;
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final loc = data["location"];
    if (loc == null) return;

    final lat = (loc["latitude"] as num).toDouble();
    final lng = (loc["longitude"] as num).toDouble();
    final displayName = (data["displayName"]?["text"] as String?) ?? s.primaryText;

    await _goToExactView(lat: lat, lng: lng, zoom: 17, bearing: 0, tilt: 0);

    final id = 'sel_${placeId.substring(0, 10)}';
    final newMarker = Marker(
      markerId: MarkerId(id),
      position: LatLng(lat, lng),
      infoWindow: InfoWindow(title: displayName),
    );

    setState(() {
      _markers = _markers.where((m) => !m.markerId.value.startsWith('sel_')).toSet()
        ..add(newMarker);
      _suggestions = [];
      _searchFocus.unfocus();
      _sessionToken = _uuid.v4();
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _camera,
            onMapCreated: _onMapCreated,
            onCameraMove: _onCameraMove,
            mapType: MapType.hybrid,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            myLocationEnabled: _myLocationEnabled,
            myLocationButtonEnabled: true,
            markers: _markers,
            compassEnabled: true,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
          ),

          // ====== Search bar + suggestions ======
          Positioned(
            top: topPadding + 64,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search address or place',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : (_searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _searchCtrl.clear();
                                      _suggestions = [];
                                    });
                                  },
                                )
                              : null),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                    ),
                    onSubmitted: (_) {
                      if (_suggestions.isEmpty && _searchCtrl.text.trim().isNotEmpty) {
                        _fetchAutocomplete(_searchCtrl.text.trim());
                      }
                    },
                  ),
                ),

                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    constraints: const BoxConstraints(maxHeight: 280),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(blurRadius: 8, spreadRadius: 0.5, color: Colors.black26)],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final s = _suggestions[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(s.primaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: s.secondaryText == null
                              ? null
                              : Text(s.secondaryText!, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _onSuggestionTap(s),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Back button
          Positioned(
            top: topPadding + 12,
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
            onPressed: namedArea,
            icon: const Icon(Icons.print),
            label: const Text('Setup Button'),
          ),
        ],
      ),
    );
  }
}

// ====== Helper model for suggestions ======
class _Suggestion {
  final String placeId;
  final String primaryText;
  final String? secondaryText;

  _Suggestion({required this.placeId, required this.primaryText, this.secondaryText});

  factory _Suggestion.fromJson(Map<String, dynamic> json) {
    final p = json["placePrediction"] ?? {};
    final text = (p["text"] ?? {})["text"] as String? ?? "";
    String primary = text;
    String? secondary;
    final idx = text.indexOf(',');
    if (idx > 0) {
      primary = text.substring(0, idx).trim();
      secondary = text.substring(idx + 1).trim();
    }
    return _Suggestion(
      placeId: p["placeId"] as String? ?? "",
      primaryText: primary.isEmpty ? (p["placeId"] as String? ?? "") : primary,
      secondaryText: secondary,
    );
  }
}


// // ignore_for_file: prefer_final_fields, unnecessary_string_interpolations

// import 'dart:async';
// import 'dart:convert';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:http/http.dart' as http;
// import 'package:luckygo_admin/global.dart';
// import 'package:luckygo_admin/home_page.dart';
// import 'package:uuid/uuid.dart';

// class SetMapViewport extends StatefulWidget {
//   const SetMapViewport({super.key});

//   @override
//   State<SetMapViewport> createState() => _SetMapViewportState();
// }

// class _SetMapViewportState extends State<SetMapViewport> {
//   final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();

//   // ====== Autocomplete state ======
//   final TextEditingController _searchCtrl = TextEditingController();
//   final FocusNode _searchFocus = FocusNode();
//   Timer? _debounce;
//   final _uuid = const Uuid();
//   String _sessionToken = "";
//   List<_Suggestion> _suggestions = [];
//   bool _isSearching = false;

//   // === Places API keys copied from luckygo_passenger (tries key[0], then key[1] on API_KEY_INVALID) ===
//   final List<String> _placesKeys = const [
//     'AIzaSyBr2bdTwwE-x9PyHSArUbCgZ_BsDupqmfA',
//     'AIzaSyDa5S3_IbRkjAJsH53VIXca0ZPLm9WcSHw',
//   ];
//   int _activePlacesKey = 0;

//   // Live camera (updated by onCameraMove). Placeholder; we jump to GPS on start.
//   CameraPosition _camera = const CameraPosition(
//     target: LatLng(5.99363442011087, 116.13621857625759),

//     zoom: 12,
//     tilt: 0,
//     bearing: 0,
//   );

//   StreamSubscription<Position>? _posSub;
//   LatLng? _myLatLng;
//   bool _myLocationEnabled = false;

//   static Set<Marker> _markers = {
//     const Marker(
//       markerId: MarkerId('kkia'),
//       position: LatLng(5.9372, 116.0515),
//       infoWindow: InfoWindow(title: 'KKIA'),
//     ),
//   };

//   // gates to ensure we jump to user once (when both map + GPS are ready)
//   bool _mapReady = false;
//   bool _centeredOnUserOnce = false;

//   @override
//   void initState() {
//     super.initState();
//     _ensureLocationPermission();
//     _listenLocation();

//     _sessionToken = _uuid.v4();
//     _searchCtrl.addListener(_onSearchChanged);
//   }

//   @override
//   void dispose() {
//     _debounce?.cancel();
//     _posSub?.cancel();
//     _searchCtrl.removeListener(_onSearchChanged);
//     _searchCtrl.dispose();
//     _searchFocus.dispose();
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
//       await _maybeCenterOnUserOnce();
//     });
//   }

//   // Jump once to user's current location (NO animation)
//   Future<void> _maybeCenterOnUserOnce() async {
//     if (_centeredOnUserOnce || !_mapReady || _myLatLng == null) return;
//     _centeredOnUserOnce = true;

//     final map = await _controller.future;
//     final cam = CameraPosition(
//       target: _myLatLng!,
//       zoom: 16,  // pick your default street-level zoom
//       tilt: 0,
//       bearing: 0,
//     );
//     await map.moveCamera(CameraUpdate.newCameraPosition(cam)); // instant
//     if (!mounted) return;
//     setState(() => _camera = cam);
//   }

//   void _onMapCreated(GoogleMapController c) {
//     if (!_controller.isCompleted) _controller.complete(c);
//     _mapReady = true;
//     _maybeCenterOnUserOnce();
//   }

//   void _onCameraMove(CameraPosition cam) {
//     _camera = cam;
//     // ignore: avoid_print
//     print('Rotation: ${cam.bearing.toStringAsFixed(2)}°, '
//         'Zoom: ${cam.zoom.toStringAsFixed(2)}, '
//         'Target: ${cam.target.latitude.toStringAsFixed(5)}, ${cam.target.longitude.toStringAsFixed(5)}, '
//         'Tilt: ${cam.tilt.toStringAsFixed(1)}°');
//     if (mounted) setState(() {}); // update the HUD
//   }

//   Future<void> _goToExactView({
//     required double lat,
//     required double lng,
//     required double zoom,
//     required double bearing,
//     required double tilt,
//   }) async {
//     final map = await _controller.future;
//     final cam = CameraPosition(
//       target: LatLng(lat, lng),
//       zoom: zoom,
//       tilt: tilt,
//       bearing: bearing,
//     );
//     await map.animateCamera(CameraUpdate.newCameraPosition(cam)); // uses default platform animation
//     if (!mounted) return;
//     setState(() => _camera = cam); // keep HUD in sync
//   }

//   void namedArea() {

//     showDialog(
//       context: context,
//       builder: (context) {
//         return AlertDialog(
//           title: const Text('Enter a name for your selected area'),
//           content: TextField(
//             controller: areaNameController,
//             decoration: const InputDecoration(
//               hintText: 'Area name',
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: () {
//                 Navigator.of(context).pop();
//               },
//               child: const Text('Close'),
//             ),
//             ElevatedButton(
//               onPressed: () async {
//                 await setupButton();
//                 Navigator.of(context).pop();
//               },
//               child: const Text('Create'),
//             ),
//           ],
//         );
//       },
//     );
//   }

//   Future<void> setupButton() async {



//     await FirebaseFirestore.instance
//     .collection(negara)
//     .doc(negeri)
//     .collection('information')
//     .doc('geo_fencing')
//     .collection('geo_fencing_button')
//     .doc('${getFormattedDate()}(${areaNameController.text})')
//     .set({
//       'name': '${areaNameController.text}',
//       'bearing': '${_camera.bearing.toStringAsFixed(1)}',
//       'zoom': '${_camera.zoom.toStringAsFixed(2)}',
//       'tilt': '${_camera.tilt.toStringAsFixed(1)}',
//       'center': '${_camera.target.latitude.toStringAsFixed(5)}, ${_camera.target.longitude.toStringAsFixed(5)}',
//       'myloc': '${_myLatLng == null ? '—' : '${_myLatLng!.latitude.toStringAsFixed(5)}, ${_myLatLng!.longitude.toStringAsFixed(5)}'}'
//     });



//     final data = '''
//       Bearing: ${_camera.bearing.toStringAsFixed(1)}°
//       Zoom: ${_camera.zoom.toStringAsFixed(2)}
//       Tilt: ${_camera.tilt.toStringAsFixed(1)}°
//       Center: ${_camera.target.latitude.toStringAsFixed(5)}, ${_camera.target.longitude.toStringAsFixed(5)}
//       MyLoc: ${_myLatLng == null ? '—' : '${_myLatLng!.latitude.toStringAsFixed(5)}, ${_myLatLng!.longitude.toStringAsFixed(5)}'}
//       ''';
//     // ignore: avoid_print
//     print(data);
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('View data printed to console')),);











    
//   }

//   // ====== Autocomplete logic ======
//   void _onSearchChanged() {
//     final text = _searchCtrl.text.trim();
//     if (_debounce?.isActive ?? false) _debounce!.cancel();
//     _debounce = Timer(const Duration(milliseconds: 350), () async {
//       if (text.isEmpty) {
//         if (mounted) setState(() => _suggestions = []);
//         return;
//       }
//       await _fetchAutocomplete(text);
//     });
//   }

//   Map<String, String> _placesHeaders({String fieldMask = ''}) {
//     return {
//       "Content-Type": "application/json",
//       "X-Goog-Api-Key": _placesKeys[_activePlacesKey],
//       if (fieldMask.isNotEmpty) "X-Goog-FieldMask": fieldMask,
//     };
//   }

//   Future<http.Response> _placesPost(Uri uri, Map<String, dynamic> body, {String fieldMask = ''}) async {
//     http.Response res = await http.post(uri, headers: _placesHeaders(fieldMask: fieldMask), body: jsonEncode(body));
//     if (res.statusCode == 400 && res.body.contains('API_KEY_INVALID') && _activePlacesKey == 0) {
//       // try the 2nd key
//       _activePlacesKey = 1;
//       res = await http.post(uri, headers: _placesHeaders(fieldMask: fieldMask), body: jsonEncode(body));
//     }
//     return res;
//   }

//   Future<http.Response> _placesGet(Uri uri, {String fieldMask = ''}) async {
//     http.Response res = await http.get(uri, headers: _placesHeaders(fieldMask: fieldMask));
//     if (res.statusCode == 400 && res.body.contains('API_KEY_INVALID') && _activePlacesKey == 0) {
//       _activePlacesKey = 1;
//       res = await http.get(uri, headers: _placesHeaders(fieldMask: fieldMask));
//     }
//     return res;
//   }

//   Future<void> _fetchAutocomplete(String query) async {
//     setState(() => _isSearching = true);

//     // Bias around current camera center for better local results
//     final biasLat = _camera.target.latitude;
//     final biasLng = _camera.target.longitude;

//     final uri = Uri.parse('https://places.googleapis.com/v1/places:autocomplete');
//     final body = {
//       "input": query,
//       "sessionToken": _sessionToken,
//       "locationBias": {
//         "circle": {
//           "center": {"latitude": biasLat, "longitude": biasLng},
//           "radius": 30000.0 // 30 km bias
//         }
//       }
//     };

//     final res = await _placesPost(
//       uri,
//       body,
//       fieldMask: "suggestions.placePrediction.placeId,suggestions.placePrediction.text",
//     );

//     if (!mounted) return;
//     setState(() => _isSearching = false);

//     if (res.statusCode == 200) {
//       final data = jsonDecode(res.body) as Map<String, dynamic>;
//       final list = (data["suggestions"] as List<dynamic>? ?? [])
//           .map((s) => _Suggestion.fromJson(s))
//           .toList();
//       setState(() => _suggestions = list);
//     } else {
//       // ignore: avoid_print
//       print('Autocomplete error: ${res.statusCode} ${res.body}');
//       setState(() => _suggestions = []);
//     }
//   }

//   Future<void> _onSuggestionTap(_Suggestion s) async {
//     // Fetch details for lat/lng
//     final placeId = s.placeId;
//     final uri = Uri.parse('https://places.googleapis.com/v1/places/$placeId');

//     final res = await _placesGet(
//       uri,
//       fieldMask: "id,displayName,location",
//     );

//     if (res.statusCode != 200) {
//       // ignore: avoid_print
//       print('Place details error: ${res.statusCode} ${res.body}');
//       return;
//     }

//     final data = jsonDecode(res.body) as Map<String, dynamic>;
//     final loc = data["location"];
//     if (loc == null) return;

//     final lat = (loc["latitude"] as num).toDouble();
//     final lng = (loc["longitude"] as num).toDouble();
//     final displayName = (data["displayName"]?["text"] as String?) ?? s.primaryText;

//     // Animate camera
//     await _goToExactView(lat: lat, lng: lng, zoom: 17, bearing: 0, tilt: 0);

//     // Drop a marker for the selected place
//     final id = 'sel_${placeId.substring(0, 10)}';
//     final newMarker = Marker(
//       markerId: MarkerId(id),
//       position: LatLng(lat, lng),
//       infoWindow: InfoWindow(title: displayName),
//     );

//     setState(() {
//       // Replace existing "selected place" marker by removing any previous sel_*
//       _markers = _markers.where((m) => !m.markerId.value.startsWith('sel_')).toSet()
//         ..add(newMarker);
//       // Clear suggestions & collapse list
//       _suggestions = [];
//       _searchFocus.unfocus();
//       // Refresh session token for next full search flow (recommended by Google)
//       _sessionToken = _uuid.v4();
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     final topPadding = MediaQuery.of(context).padding.top;

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

//           // ====== Search bar + suggestions ======
//           Positioned(
//             top: topPadding + 64,
//             left: 12,
//             right: 12,
//             child: Column(
//               children: [
//                 Material(
//                   elevation: 4,
//                   borderRadius: BorderRadius.circular(12),
//                   child: TextField(
//                     controller: _searchCtrl,
//                     focusNode: _searchFocus,
//                     textInputAction: TextInputAction.search,
//                     decoration: InputDecoration(
//                       hintText: 'Search address or place',
//                       prefixIcon: const Icon(Icons.search),
//                       suffixIcon: _isSearching
//                           ? const Padding(
//                               padding: EdgeInsets.all(12.0),
//                               child: SizedBox(
//                                 width: 18, height: 18,
//                                 child: CircularProgressIndicator(strokeWidth: 2),
//                               ),
//                             )
//                           : (_searchCtrl.text.isNotEmpty
//                               ? IconButton(
//                                   icon: const Icon(Icons.clear),
//                                   onPressed: () {
//                                     setState(() {
//                                       _searchCtrl.clear();
//                                       _suggestions = [];
//                                     });
//                                   },
//                                 )
//                               : null),
//                       border: OutlineInputBorder(
//                         borderRadius: BorderRadius.circular(12),
//                         borderSide: BorderSide.none,
//                       ),
//                       filled: true,
//                     ),
//                     onSubmitted: (_) {
//                       if (_suggestions.isEmpty && _searchCtrl.text.trim().isNotEmpty) {
//                         _fetchAutocomplete(_searchCtrl.text.trim());
//                       }
//                     },
//                   ),
//                 ),

//                 if (_suggestions.isNotEmpty)
//                   Container(
//                     margin: const EdgeInsets.only(top: 6),
//                     constraints: const BoxConstraints(maxHeight: 280),
//                     decoration: BoxDecoration(
//                       color: Theme.of(context).cardColor,
//                       borderRadius: BorderRadius.circular(12),
//                       boxShadow: const [BoxShadow(blurRadius: 8, spreadRadius: 0.5, color: Colors.black26)],
//                     ),
//                     child: ListView.separated(
//                       shrinkWrap: true,
//                       itemCount: _suggestions.length,
//                       separatorBuilder: (_, __) => const Divider(height: 1),
//                       itemBuilder: (context, i) {
//                         final s = _suggestions[i];
//                         return ListTile(
//                           dense: true,
//                           leading: const Icon(Icons.place_outlined),
//                           title: Text(s.primaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
//                           subtitle: s.secondaryText == null
//                               ? null
//                               : Text(s.secondaryText!, maxLines: 1, overflow: TextOverflow.ellipsis),
//                           onTap: () => _onSuggestionTap(s),
//                         );
//                       },
//                     ),
//                   ),
//               ],
//             ),
//           ),

//           // Back button
//           Positioned(
//             top: topPadding + 12,
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

//       floatingActionButton: Column(
//         mainAxisSize: MainAxisSize.min,
//         crossAxisAlignment: CrossAxisAlignment.end,
//         children: [
//           FloatingActionButton.extended(
//             heroTag: 'printview',
//             onPressed: namedArea,
//             icon: const Icon(Icons.print),
//             label: const Text('Setup Button'),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // ====== Helper model for suggestions ======
// class _Suggestion {
//   final String placeId;
//   final String primaryText;   // main name / line
//   final String? secondaryText; // remainder of address

//   _Suggestion({required this.placeId, required this.primaryText, this.secondaryText});

//   factory _Suggestion.fromJson(Map<String, dynamic> json) {
//     // json shape: { "placePrediction": { "placeId": "...", "text": { "text": "..."} } }
//     final p = json["placePrediction"] ?? {};
//     final text = (p["text"] ?? {})["text"] as String? ?? "";
//     // Split at first comma for nicer UI
//     String primary = text;
//     String? secondary;
//     final idx = text.indexOf(',');
//     if (idx > 0) {
//       primary = text.substring(0, idx).trim();
//       secondary = text.substring(idx + 1).trim();
//     }
//     return _Suggestion(
//       placeId: p["placeId"] as String? ?? "",
//       primaryText: primary.isEmpty ? (p["placeId"] as String? ?? "") : primary,
//       secondaryText: secondary,
//     );
//   }
// }

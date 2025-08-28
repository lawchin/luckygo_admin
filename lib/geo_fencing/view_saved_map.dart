// ignore_for_file: prefer_final_fields

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:luckygo_admin/global.dart'; // expects negara, negeri

enum ActiveColor { red, blue }

class ViewSavedMap extends StatefulWidget {
  /// Firestore values; this page parses them.
  /// center/myloc: "6.01, 116.12" | [6.01, 116.12] | {lat: 6.01, lng: 116.12}
  /// zoom/bearing/tilt: "17.0" | 17 | 17.0
  final dynamic center;
  final dynamic zoom;
  final dynamic bearing;
  final dynamic tilt;
  final dynamic myloc;
  final String? name; // area name (doc selection)

  const ViewSavedMap({
    super.key,
    required this.center,
    this.zoom,
    this.bearing,
    this.tilt,
    this.myloc,
    this.name,
  });

  @override
  State<ViewSavedMap> createState() => _ViewSavedMapState();
}

class _ViewSavedMapState extends State<ViewSavedMap> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  PersistentBottomSheetController? _sheetController;

  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  static const LatLng _inanam = LatLng(6.0146, 116.1230);

  late CameraPosition _camera;
  late CameraPosition _initialCam;
  bool _myLocationEnabled = false;

  // Editing mode (default red = outer)
  ActiveColor _activeColor = ActiveColor.red;

  // Points
  final List<LatLng> _redPoints = [];  // outer ring (red)
  final List<LatLng> _bluePoints = []; // hole ring (blue)

  // The single area doc ID (null until first save)
  String? _areaDocId;

  // Track current "active" state of the doc (defaults to true on create)
  bool _docActive = true;

  // ===== Marker edit state =====
  ActiveColor? _editingColor;
  int? _editingIndex;
  LatLng? _originalLatLng; // to revert on Cancel
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lngCtrl = TextEditingController();

  // ---------- helpers ----------
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

  String _nowIdStamp() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection(negara)
          .doc(negeri)
          .collection('information')
          .doc('geo_fencing')
          .collection('all_geo_fencing');

  // Point-in-polygon (ray casting). Treat lat as x and lng as y consistently.
  bool _pointInPolygon(LatLng p, List<LatLng> poly) {
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].latitude, yi = poly[i].longitude;
      final xj = poly[j].latitude, yj = poly[j].longitude;
      final denom = (yj - yi);
      final intersect = ((yi > p.longitude) != (yj > p.longitude)) &&
          (p.latitude <
              (xj - xi) * (p.longitude - yi) / (denom == 0 ? 1e-12 : denom) +
                  xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  // ------------------------------------

  @override
  void initState() {
    super.initState();

    final LatLng center = _toLatLng(widget.center) ?? _inanam;
    final double zoom = _toDouble(widget.zoom) ?? 14.0;
    final double bearing = _toDouble(widget.bearing) ?? 0.0;
    final double tilt = _toDouble(widget.tilt) ?? 0.0;

    _initialCam =
        CameraPosition(target: center, zoom: zoom, bearing: bearing, tilt: tilt);
    _camera = _initialCam;

    _ensureLocationPermission();
    _loadExistingAreaDoc();
  }

  @override
  void dispose() {
    _sheetController?.close();
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
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      setState(() => _myLocationEnabled = false);
      return;
    }
    setState(() => _myLocationEnabled = true);
  }

  void _onMapCreated(GoogleMapController c) async {
    if (!_controller.isCompleted) _controller.complete(c);
    final map = await _controller.future;
    await map.moveCamera(CameraUpdate.newCameraPosition(_initialCam));
  }

  void _onCameraMove(CameraPosition cam) {
    _camera = cam;
  }

  // --- Editing handlers ---
  void _onMapTap(LatLng pos) {
    setState(() {
      if (_activeColor == ActiveColor.red) {
        _redPoints.add(pos);
      } else {
        _bluePoints.add(pos);
      }
    });
  }

  void _removeLastMarker() {
    setState(() {
      if (_activeColor == ActiveColor.red && _redPoints.isNotEmpty) {
        _redPoints.removeLast();
      } else if (_activeColor == ActiveColor.blue && _bluePoints.isNotEmpty) {
        _bluePoints.removeLast();
      }
    });
  }

  void _clearMarkers() {
    setState(() {
      if (_activeColor == ActiveColor.red) {
        _redPoints.clear();
      } else {
        _bluePoints.clear();
      }
    });
  }

  // ---------- Load (no server orderBy; client sort) ----------
  Future<void> _loadExistingAreaDoc() async {
    final areaName =
        (widget.name == null || widget.name!.trim().isEmpty) ? null : widget.name!.trim();

    try {
      Query<Map<String, dynamic>> q = _col;
      if (areaName != null) q = q.where('name', isEqualTo: areaName);

      final snap = await q.get();

      // newest first by created_at
      final docs = [...snap.docs];
      docs.sort((a, b) {
        final ta = a.data()['created_at'];
        final tb = b.data()['created_at'];
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return (tb as Timestamp).compareTo(ta as Timestamp);
      });

      _redPoints.clear();
      _bluePoints.clear();
      _areaDocId = null;
      _docActive = true;

      // Prefer unified doc (donut/outer_only/hole_only)
      QueryDocumentSnapshot<Map<String, dynamic>>? bestDoc;
      for (final d in docs) {
        final mode = (d.data()['mode'] ?? '').toString();
        if (mode == 'donut' || mode == 'outer_only' || mode == 'hole_only') {
          bestDoc = d;
          break;
        }
      }

      if (bestDoc != null) {
        final data = bestDoc!.data();
        final mode = (data['mode'] ?? '').toString();

        // pick up active (default true if missing)
        _docActive = (data['active'] as bool?) ?? true;

        if (mode != 'hole_only') {
          final outer = (data['outer_points'] as List?) ?? [];
          for (final p in outer) {
            if (p is Map) {
              final lat = _toDouble(p['lat']);
              final lng = _toDouble(p['lng']);
              if (lat != null && lng != null) _redPoints.add(LatLng(lat, lng));
            }
          }
        }

        // prefer new flat field 'hole_points'; fallback to legacy 'holes[0]'
        if (mode != 'outer_only') {
          final holesFlat = (data['hole_points'] as List?) ?? [];
          if (holesFlat.isNotEmpty) {
            for (final p in holesFlat) {
              if (p is Map) {
                final lat = _toDouble(p['lat']);
                final lng = _toDouble(p['lng']);
                if (lat != null && lng != null) _bluePoints.add(LatLng(lat, lng));
              }
            }
          } else {
            final holesLegacy = (data['holes'] as List?) ?? [];
            if (holesLegacy.isNotEmpty && holesLegacy.first is List) {
              for (final p in (holesLegacy.first as List)) {
                if (p is Map) {
                  final lat = _toDouble(p['lat']);
                  final lng = _toDouble(p['lng']);
                  if (lat != null && lng != null) _bluePoints.add(LatLng(lat, lng));
                }
              }
            }
          }
        }

        _areaDocId = bestDoc!.id;
      }

      if (mounted) setState(() {});
    } catch (e) {
      // ignore: avoid_print
      print('Load geofence failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load geofence: $e')),
      );
    }
  }

  // ---------- Single submit for the whole area (one doc, same ID) ----------
  Future<void> _submitArea() async {
    final hasOuter = _redPoints.length >= 3;
    final hasHole  = _bluePoints.length >= 3;
    if (!hasOuter && !hasHole) return;

    // Only when both exist, enforce hole inside outer
    if (hasOuter && hasHole) {
      final allInside = _bluePoints.every((p) => _pointInPolygon(p, _redPoints));
      if (!allInside) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All blue (hole) points must be inside the red polygon')),
        );
        return;
      }
    }

    final areaName =
        (widget.name == null || widget.name!.trim().isEmpty) ? 'Unnamed' : widget.name!.trim();

    final mode = hasOuter && hasHole
        ? 'donut'
        : (hasOuter ? 'outer_only' : 'hole_only');

    final outerJson = hasOuter
        ? _redPoints
            .map((p) => {
                  'lat': double.parse(p.latitude.toStringAsFixed(7)),
                  'lng': double.parse(p.longitude.toStringAsFixed(7)),
                })
            .toList()
        : [];

    final holeJson = hasHole
        ? _bluePoints
            .map((p) => {
                  'lat': double.parse(p.latitude.toStringAsFixed(7)),
                  'lng': double.parse(p.longitude.toStringAsFixed(7)),
                })
            .toList()
        : [];

    // Include/keep "active"
    final payload = <String, dynamic>{
      'name': areaName,
      'mode': mode,
      'active': _docActive, // <-- keep current active state (true on create)
      'outer_points': outerJson,
      'hole_points': holeJson, // flat (no nested arrays)
      'camera': {
        'lat': double.parse(_camera.target.latitude.toStringAsFixed(7)),
        'lng': double.parse(_camera.target.longitude.toStringAsFixed(7)),
        'zoom': double.parse(_camera.zoom.toStringAsFixed(6)),
        'bearing': double.parse(_camera.bearing.toStringAsFixed(6)),
        'tilt': double.parse(_camera.tilt.toStringAsFixed(6)),
      },
    };

    try {
      if (_areaDocId == null) {
        // cleanup any older docs with same name (legacy)
        final old = await _col.where('name', isEqualTo: areaName).get();
        if (old.docs.isNotEmpty) {
          final batch = FirebaseFirestore.instance.batch();
          for (final d in old.docs) {
            batch.delete(d.reference);
          }
          await batch.commit();
        }

        final newId = '${_nowIdStamp()}($areaName)';
        payload['created_at'] = FieldValue.serverTimestamp();
        payload['active'] = true; // <-- always true on create
        await _col.doc(newId).set(payload);
        _areaDocId = newId;
        _docActive = true;
      } else {
        payload['updated_at'] = FieldValue.serverTimestamp();
        await _col.doc(_areaDocId!).set(payload, SetOptions(merge: false));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: $areaName ($mode)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  // ===== Marker editor =====
  void _openMarkerEditor(ActiveColor color, int index) {
    _editingColor = color;
    _editingIndex = index;
    final LatLng current =
        color == ActiveColor.red ? _redPoints[index] : _bluePoints[index];
    _originalLatLng = current;
    _latCtrl.text = current.latitude.toStringAsFixed(7);
    _lngCtrl.text = current.longitude.toStringAsFixed(7);

    _sheetController?.close();
    _sheetController = _scaffoldKey.currentState?.showBottomSheet(
      (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color == ActiveColor.red ? Colors.red : Colors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  color == ActiveColor.red
                      ? 'Edit Red Marker'
                      : 'Edit Blue Marker',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lngCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelEdit,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _applyEdit,
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 8,
    );
  }

  void _cancelEdit() {
    if (_editingColor != null &&
        _editingIndex != null &&
        _originalLatLng != null) {
      setState(() {
        final list =
            _editingColor == ActiveColor.red ? _redPoints : _bluePoints;
        if (_editingIndex! >= 0 && _editingIndex! < list.length) {
          list[_editingIndex!] = _originalLatLng!;
        }
      });
    }
    _sheetController?.close();
    _sheetController = null;
    _editingColor = null;
    _editingIndex = null;
    _originalLatLng = null;
  }

  void _applyEdit() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null || lat.isNaN || lng.isNaN) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid latitude/longitude')),
      );
      return;
    }

    setState(() {
      final list =
          _editingColor == ActiveColor.red ? _redPoints : _bluePoints;
      if (_editingIndex != null &&
          _editingIndex! >= 0 &&
          _editingIndex! < list.length) {
        list[_editingIndex!] = LatLng(lat, lng);
      }
    });

    _sheetController?.close();
    _sheetController = null;
    _editingColor = null;
    _editingIndex = null;
    _originalLatLng = null;
  }

  // Update editor fields if the same marker was dragged while the editor is open
  void _syncEditorFieldsIfEditing(ActiveColor color, int index, LatLng newPos) {
    if (_editingColor == color && _editingIndex == index && _sheetController != null) {
      _latCtrl.text = newPos.latitude.toStringAsFixed(7);
      _lngCtrl.text = newPos.longitude.toStringAsFixed(7);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;

    // Markers (draggable + tappable to open editor)
    final Set<Marker> markers = {
      ..._redPoints.asMap().entries.map(
            (e) => Marker(
              markerId: MarkerId('red_${e.key}'),
              position: e.value,
              draggable: true,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              onTap: () => _openMarkerEditor(ActiveColor.red, e.key),
              onDragStart: (_) {
                if (_editingColor == ActiveColor.red && _editingIndex == e.key) {
                  _originalLatLng = _redPoints[e.key]; // in case user drags while editor open
                }
              },
              onDragEnd: (pos) {
                setState(() => _redPoints[e.key] = pos);
                _syncEditorFieldsIfEditing(ActiveColor.red, e.key, pos);
              },
            ),
          ),
      ..._bluePoints.asMap().entries.map(
            (e) => Marker(
              markerId: MarkerId('blue_${e.key}'),
              position: e.value,
              draggable: true,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
              onTap: () => _openMarkerEditor(ActiveColor.blue, e.key),
              onDragStart: (_) {
                if (_editingColor == ActiveColor.blue && _editingIndex == e.key) {
                  _originalLatLng = _bluePoints[e.key];
                }
              },
              onDragEnd: (pos) {
                setState(() => _bluePoints[e.key] = pos);
                _syncEditorFieldsIfEditing(ActiveColor.blue, e.key, pos);
              },
            ),
          ),
    };

    // POLYGONS (donut + blue outline when both exist)
    final Set<Polygon> polygons = {};
    if (_redPoints.length >= 3 && _bluePoints.length >= 3) {
      polygons.add(
        Polygon(
          polygonId: const PolygonId('donut'),
          points: _redPoints,
          holes: [_bluePoints],
          strokeColor: Colors.red,
          strokeWidth: 2,
          fillColor: Colors.red.withOpacity(0.15),
          zIndex: 1,
        ),
      );
      polygons.add(
        Polygon(
          polygonId: const PolygonId('blueOutline'),
          points: _bluePoints,
          strokeColor: Colors.blue,
          strokeWidth: 2,
          fillColor: Colors.transparent,
          zIndex: 2,
        ),
      );
    } else {
      if (_redPoints.length >= 3) {
        polygons.add(
          Polygon(
            polygonId: const PolygonId('outer'),
            points: _redPoints,
            strokeColor: Colors.red,
            strokeWidth: 2,
            fillColor: Colors.red.withOpacity(0.15),
            zIndex: 1,
          ),
        );
      }
      if (_bluePoints.length >= 3) {
        polygons.add(
          Polygon(
            polygonId: const PolygonId('holeOnly'),
            points: _bluePoints,
            strokeColor: Colors.blue,
            strokeWidth: 2,
            fillColor: Colors.blue.withOpacity(0.15),
            zIndex: 1,
          ),
        );
      }
    }

    final canSubmit = _redPoints.length >= 3 || _bluePoints.length >= 3;

    // Buttons
    final backBtn = FloatingActionButton(
      heroTag: 'backBtn',
      mini: true,
      backgroundColor: Colors.black87,
      onPressed: () => Navigator.of(context).maybePop(),
      child: const Icon(Icons.arrow_back, color: Colors.white),
    );

    final redBtn = FloatingActionButton(
      heroTag: 'redBtn',
      mini: true,
      backgroundColor:
          _activeColor == ActiveColor.red ? Colors.red : Colors.red.withOpacity(0.4),
      onPressed: () => setState(() => _activeColor = ActiveColor.red),
      child: const Icon(Icons.circle, color: Colors.white),
      tooltip: 'Edit red (outer)',
    );

    final blueBtn = FloatingActionButton(
      heroTag: 'blueBtn',
      mini: true,
      backgroundColor:
          _activeColor == ActiveColor.blue ? Colors.blue : Colors.blue.withOpacity(0.4),
      onPressed: () => setState(() => _activeColor = ActiveColor.blue),
      child: const Icon(Icons.circle, color: Colors.white),
      tooltip: 'Edit blue (hole)',
    );

    final submitBtn = FloatingActionButton(
      heroTag: 'submitBtn',
      mini: true,
      backgroundColor: canSubmit ? Colors.teal : Colors.grey.shade500,
      onPressed: canSubmit ? _submitArea : null,
      child: const Icon(Icons.save, color: Colors.white),
      tooltip: 'Submit / update area (same ID, includes "active")',
    );

    final removeBtn = FloatingActionButton(
      heroTag: 'removeBtn',
      mini: true,
      backgroundColor: Colors.grey.shade800,
      onPressed: _removeLastMarker,
      child: const Icon(Icons.undo, color: Colors.white),
      tooltip: 'Remove last marker',
    );

    final clearBtn = FloatingActionButton(
      heroTag: 'clearBtn',
      mini: true,
      backgroundColor: Colors.grey.shade800,
      onPressed: _clearMarkers,
      child: const Icon(Icons.clear, color: Colors.white),
      tooltip: 'Clear markers',
    );

    // Portrait: bottom center row
    final portraitRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        redBtn,
        const SizedBox(width: 12),
        blueBtn,
        const SizedBox(width: 24),
        submitBtn,
        const SizedBox(width: 24),
        removeBtn,
        const SizedBox(width: 8),
        clearBtn,
      ],
    );

    // Landscape: right-side column
    final landscapeColumn = Column(
      children: [
        redBtn,
        const SizedBox(height: 8),
        blueBtn,
        const SizedBox(height: 20),
        submitBtn,
        const SizedBox(height: 20),
        removeBtn,
        const SizedBox(height: 8),
        clearBtn,
      ],
    );

    return Scaffold(
      key: _scaffoldKey,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCam,
            onMapCreated: _onMapCreated,
            onCameraMove: _onCameraMove,
            mapType: MapType.hybrid,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            myLocationEnabled: _myLocationEnabled,
            myLocationButtonEnabled: true,
            markers: markers,
            polygons: polygons,
            compassEnabled: true,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
            onTap: _onMapTap,
          ),

          // Back
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            child: backBtn,
          ),

          // Controls by orientation
          if (orientation == Orientation.portrait)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 0,
              right: 0,
              child: portraitRow,
            )
          else
            Positioned(
              right: 16,
              top: (MediaQuery.of(context).size.height / 2) - 120,
              child: landscapeColumn,
            ),
        ],
      ),
    );
  }
}

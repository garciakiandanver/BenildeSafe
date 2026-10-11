import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';

class AdminBoundaryEditorScreen extends StatefulWidget {
  final Map<String, dynamic> campus;
  final String token;

  const AdminBoundaryEditorScreen({
    super.key,
    required this.campus,
    required this.token,
  });

  @override
  State<AdminBoundaryEditorScreen> createState() =>
      _AdminBoundaryEditorScreenState();
}

class _AdminBoundaryEditorScreenState extends State<AdminBoundaryEditorScreen> {
  final List<LatLng> _points = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingBoundary();
  }

  void _loadExistingBoundary() {
    try {
      final boundary = widget.campus['boundary_coordinates'];
      if (boundary == null) return;
      final coords = boundary['coordinates'][0] as List;
      final points = coords.map((c) {
        final lng = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        return LatLng(lat, lng);
      }).toList();
      if (points.length > 1 &&
          points.first.latitude == points.last.latitude &&
          points.first.longitude == points.last.longitude) {
        points.removeLast();
      }
      setState(() {
        _points.addAll(points);
      });
    } catch (_) {}
  }

  LatLng _getCenter() {
    if (_points.isEmpty) {
      final lat =
          double.tryParse(widget.campus['latitude'].toString()) ?? 14.8449;
      final lng =
          double.tryParse(widget.campus['longitude'].toString()) ?? 120.2903;
      return LatLng(lat, lng);
    }
    double lat = 0, lng = 0;
    for (final p in _points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / _points.length, lng / _points.length);
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _points.add(point);
    });
  }

  void _removeLastPoint() {
    if (_points.isEmpty) return;
    setState(() {
      _points.removeLast();
    });
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Points'),
        content: const Text(
          'Are you sure you want to clear all boundary points?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _points.clear();
              });
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveBoundary() async {
    if (_points.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least 3 points to form a boundary.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Boundary'),
        content: Text(
          'Save new boundary with ${_points.length} points for ${widget.campus['campus_name']}?\n\nStudents will only be able to check in within the new boundary.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final coordinates = _points
          .map((p) => [p.longitude, p.latitude])
          .toList();

      await ApiService.updateCampusBoundary(
        token: widget.token,
        campusId: widget.campus['id'],
        coordinates: coordinates,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Boundary saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = _getCenter();

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit: ${widget.campus['campus_name']}'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _saveBoundary,
              child: const Text(
                'Save',
                style: TextStyle(
                  color: Color(0xFF005A23),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 18,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.geoloc_attendancecapstone',
              ),
              if (_points.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _points,
                      color: const Color(0xFF005A23).withValues(alpha: 0.2),
                      borderColor: const Color(0xFF005A23),
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),
              if (_points.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _points,
                      color: const Color(0xFF005A23),
                      strokeWidth: 2,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: _points.asMap().entries.map((entry) {
                  final index = entry.key;
                  final point = entry.value;
                  return Marker(
                    point: point,
                    width: 30,
                    height: 30,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _points.removeAt(index);
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: index == 0
                              ? Colors.green
                              : const Color(0xFF005A23),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.6),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(
                'Tap map to add points • Tap a point to remove it • ${_points.length} point(s)',
                style: const TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _removeLastPoint,
                    icon: const Icon(Icons.undo),
                    label: const Text('Undo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _clearAll,
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

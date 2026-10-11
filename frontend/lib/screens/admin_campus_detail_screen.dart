import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import 'admin_boundary_editor_screen.dart';

class AdminCampusDetailScreen extends StatefulWidget {
  final Map<String, dynamic> campus;
  final String token;

  const AdminCampusDetailScreen({
    super.key,
    required this.campus,
    required this.token,
  });

  @override
  State<AdminCampusDetailScreen> createState() =>
      _AdminCampusDetailScreenState();
}

class _AdminCampusDetailScreenState extends State<AdminCampusDetailScreen> {
  late Map<String, dynamic> _campus;

  @override
  void initState() {
    super.initState();
    _campus = widget.campus;
  }

  List<LatLng> _parseCoordinates() {
    try {
      final boundary = _campus['boundary_coordinates'];
      final coords = boundary['coordinates'][0] as List;
      return coords.map((c) {
        final lng = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        return LatLng(lat, lng);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  LatLng _getCenter(List<LatLng> points) {
    if (points.isEmpty) {
      final lat = double.tryParse(_campus['latitude'].toString()) ?? 14.8449;
      final lng = double.tryParse(_campus['longitude'].toString()) ?? 120.2903;
      return LatLng(lat, lng);
    }
    double lat = 0, lng = 0;
    for (final p in points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
  }

  @override
  Widget build(BuildContext context) {
    final points = _parseCoordinates();
    final center = _getCenter(points);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: Text(_campus['campus_name'] ?? 'Campus'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final updated = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => AdminBoundaryEditorScreen(
                    campus: _campus,
                    token: widget.token,
                  ),
                ),
              );
              if (!context.mounted) return;
              if (updated == true) Navigator.pop(context, true);
            },
            icon: const Icon(Icons.edit_location_alt, color: Color(0xFF005A23)),
            label: const Text(
              'Edit',
              style: TextStyle(color: Color(0xFF005A23)),
            ),
          ),
          IconButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Campus'),
                  content: Text(
                    'Are you sure you want to delete "${_campus['campus_name']}"? This cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );

              if (!context.mounted || confirm != true) return;

              try {
                await ApiService.deleteCampus(
                  token: widget.token,
                  campusId: _campus['id'],
                );

                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Campus deleted successfully.'),
                    backgroundColor: Colors.green,
                  ),
                );

                Navigator.pop(context, true);
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      error.toString().replaceFirst('Exception: ', ''),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            icon: const Icon(Icons.delete, color: Colors.red),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF005A23).withValues(alpha: 0.05),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_city, color: Color(0xFF005A23)),
                    const SizedBox(width: 8),
                    Text(
                      _campus['campus_name'] ?? '--',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Campus Code: ${_campus['campus_code'] ?? '--'}',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  'Boundary Points: ${points.isNotEmpty ? points.length - 1 : 0}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          Expanded(
            child: points.isEmpty
                ? const Center(child: Text('No boundary data available.'))
                : FlutterMap(
                    options: MapOptions(initialCenter: center, initialZoom: 17),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.example.geoloc_attendancecapstone',
                      ),
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: points,
                            color: const Color(
                              0xFF005A23,
                            ).withValues(alpha: 0.2),
                            borderColor: const Color(0xFF005A23),
                            borderStrokeWidth: 3,
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: center,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_pin,
                              color: Color(0xFF005A23),
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

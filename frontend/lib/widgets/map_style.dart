import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// How a campus map is drawn: the street map, or satellite photos.
///
/// Satellite is what an administrator needs when drawing a boundary: the
/// buildings, roads and gates are visible, so the corners can be placed on
/// them. The street map is easier to read for names.
enum CampusMapStyle { street, satellite }

/// Remembers the last choice while the app is open, so opening another campus
/// or the boundary editor does not flip the map back.
class CampusMapMemory {
  static CampusMapStyle style = CampusMapStyle.street;
}

/// The tiles for [style]. Both are free to use without a key. Satellite is
/// Esri World Imagery.
TileLayer campusTileLayer(CampusMapStyle style) {
  switch (style) {
    case CampusMapStyle.satellite:
      return TileLayer(
        urlTemplate:
            'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'World_Imagery/MapServer/tile/{z}/{y}/{x}',
        userAgentPackageName: 'com.example.geoloc_attendancecapstone',
        maxNativeZoom: 19,
      );
    case CampusMapStyle.street:
      return TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.example.geoloc_attendancecapstone',
        maxNativeZoom: 19,
      );
  }
}

/// The campus green does not show on green-and-grey photos, so the boundary
/// is drawn in yellow on satellite and stays green on the street map.
Color campusBoundaryColor(CampusMapStyle style) =>
    style == CampusMapStyle.satellite
    ? const Color(0xFFFFD60A)
    : const Color(0xFF005A23);

/// The "Map | Satellite" switch and the credit line the tile providers ask
/// for. Place it inside a [Stack] on top of the map.
class CampusMapStyleControl extends StatelessWidget {
  final CampusMapStyle style;
  final ValueChanged<CampusMapStyle> onChanged;

  /// Distance from the top and bottom edge, for screens that already put a
  /// banner or buttons there (the boundary editor).
  final double top;
  final double bottom;

  const CampusMapStyleControl({
    super.key,
    required this.style,
    required this.onChanged,
    this.top = 12,
    this.bottom = 4,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned(
          top: top,
          right: 12,
          child: Material(
            elevation: 3,
            borderRadius: BorderRadius.circular(24),
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: SegmentedButton<CampusMapStyle>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                segments: const [
                  ButtonSegment(
                    value: CampusMapStyle.street,
                    icon: Icon(Icons.map_outlined, size: 18),
                    label: Text('Map'),
                  ),
                  ButtonSegment(
                    value: CampusMapStyle.satellite,
                    icon: Icon(Icons.satellite_alt_outlined, size: 18),
                    label: Text('Satellite'),
                  ),
                ],
                selected: {style},
                onSelectionChanged: (value) {
                  CampusMapMemory.style = value.first;
                  onChanged(value.first);
                },
              ),
            ),
          ),
        ),
        Positioned(
          left: 6,
          bottom: bottom,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              style == CampusMapStyle.satellite
                  ? 'Imagery © Esri, Maxar, Earthstar Geographics'
                  : '© OpenStreetMap contributors',
              style: const TextStyle(fontSize: 10, color: Colors.black87),
            ),
          ),
        ),
      ],
    );
  }
}

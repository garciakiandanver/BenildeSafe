import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AdminAddCampusScreen extends StatefulWidget {
  final String token;

  const AdminAddCampusScreen({super.key, required this.token});

  @override
  State<AdminAddCampusScreen> createState() => _AdminAddCampusScreenState();
}

class _AdminAddCampusScreenState extends State<AdminAddCampusScreen> {
  final _campusNameController = TextEditingController();
  final _campusCodeController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  bool _isLoading = false;
  String _error = '';

  @override
  void dispose() {
    _campusNameController.dispose();
    _campusCodeController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final campusName = _campusNameController.text.trim();
    final campusCode = _campusCodeController.text.trim();
    final latStr = _latitudeController.text.trim();
    final lngStr = _longitudeController.text.trim();

    if (campusName.isEmpty ||
        campusCode.isEmpty ||
        latStr.isEmpty ||
        lngStr.isEmpty) {
      setState(() {
        _error = 'All fields are required.';
      });
      return;
    }

    final latitude = double.tryParse(latStr);
    final longitude = double.tryParse(lngStr);

    if (latitude == null || longitude == null) {
      setState(() {
        _error = 'Latitude and longitude must be valid numbers.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      await ApiService.addCampus(
        token: widget.token,
        campusName: campusName,
        campusCode: campusCode,
        latitude: latitude,
        longitude: longitude,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Campus added successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Campus')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.location_city, size: 64, color: Color(0xFF005A23)),
            const SizedBox(height: 24),

            TextField(
              controller: _campusNameController,
              decoration: const InputDecoration(
                labelText: 'Campus Name',
                hintText: 'e.g. Main Campus',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _campusCodeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Campus Code',
                hintText: 'e.g. MAIN',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.code),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _latitudeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Latitude',
                hintText: 'e.g. 14.8449',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.my_location),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _longitudeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Longitude',
                hintText: 'e.g. 120.2903',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.my_location),
              ),
            ),
            const SizedBox(height: 8),

            // Helper text
            const Text(
              'Tip: You can get the latitude and longitude from Google Maps by long-pressing a location.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),

            const SizedBox(height: 24),

            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _error,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),

            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005A23),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'ADD CAMPUS',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),

            const SizedBox(height: 12),

            const Text(
              'After adding the campus, you can set its boundary by tapping the campus and selecting Edit.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

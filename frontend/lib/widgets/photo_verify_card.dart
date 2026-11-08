import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../utils/manila_time.dart';

/// Optional photo verification, once a day, on the student's home screen.
///
/// The photo is taken with the camera only (never the gallery), and the
/// server accepts it only when the phone's GPS position is inside a campus.
/// Only the Android app offers it: a browser on a computer cannot be limited
/// to the camera.
class PhotoVerifyCard extends StatefulWidget {
  final String token;
  final Future<Position?> Function() getPosition;

  const PhotoVerifyCard({
    super.key,
    required this.token,
    required this.getPosition,
  });

  @override
  State<PhotoVerifyCard> createState() => _PhotoVerifyCardState();
}

class _PhotoVerifyCardState extends State<PhotoVerifyCard> {
  bool _loading = true;
  bool _busy = false;
  bool _verified = false;
  String _detail = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  String _clock(String? text) => ManilaTime.time(text, fallback: '');

  Future<void> _loadStatus() async {
    try {
      final result = await ApiService.getTodayPhotoStatus(token: widget.token);
      if (!mounted) return;
      setState(() {
        _verified = result['verified'] == true;
        _detail = _verified
            ? 'Verified with a photo at ${_clock(result['captured_at']?.toString())}'
                '${result['campus_name'] != null ? ', ${result['campus_name']}' : ''}.'
            : '';
        _loading = false;
      });
    } catch (_) {
      // The feature is optional: if the status cannot be loaded, hide nothing
      // else on the screen and let the student try the button.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _takePhoto() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final start = await ApiService.startPhotoVerification(token: widget.token);
      final startToken = start['start_token']?.toString() ?? '';

      final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 60,
      );
      if (file == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final bytes = await file.readAsBytes();

      final position = await widget.getPosition();
      if (position == null) {
        throw Exception('Location permission is required.');
      }

      final result = await ApiService.submitPhotoVerification(
        token: widget.token,
        startToken: startToken,
        photoBase64: base64Encode(bytes),
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        isMocked: position.isMocked,
      );
      if (!mounted) return;
      setState(() {
        _verified = true;
        _detail = result['message']?.toString() ?? 'Verified with a photo.';
      });
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() => _error = message);
      if (message.contains('already verified')) _loadStatus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _todayKey() {
    final now = ManilaTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  void _viewPhoto() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your verification photo'),
        content: FutureBuilder<Map<String, dynamic>>(
          future: ApiService.getMyPhoto(token: widget.token, date: _todayKey()),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text(
                snapshot.error.toString().replaceFirst('Exception: ', ''),
              );
            }
            final photo = snapshot.data?['photo']?.toString();
            if (photo == null || !photo.contains(',')) {
              return const Text('The photo is not available.');
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                base64Decode(photo.split(',').last),
                fit: BoxFit.contain,
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    final Widget content;
    if (_verified) {
      content = Row(
        children: [
          Icon(Icons.verified_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _detail.isEmpty ? 'Verified with a photo today.' : _detail,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: _viewPhoto, child: const Text('View')),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.photo_camera_outlined, color: muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Verify with a photo (optional)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            kIsWeb
                ? 'Photo verification is available in the Android app only.'
                : 'Take a photo of your surroundings on campus. It is checked with your location and seen only by you and the school. Once a day.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (!kIsWeb) ...[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _takePhoto,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_camera_rounded),
              label: Text(_busy ? 'Checking...' : 'Take photo'),
            ),
          ],
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(padding: const EdgeInsets.all(16), child: content),
    );
  }
}

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'admin_campus_detail_screen.dart';
import 'admin_add_campus_screen.dart';

class AdminCampusesScreen extends StatefulWidget {
  final String token;

  const AdminCampusesScreen({super.key, required this.token});

  @override
  State<AdminCampusesScreen> createState() => _AdminCampusesScreenState();
}

class _AdminCampusesScreenState extends State<AdminCampusesScreen> {
  bool _isLoading = true;
  String _error = '';
  List<dynamic> _campuses = [];

  @override
  void initState() {
    super.initState();
    _loadCampuses();
  }

  Future<void> _loadCampuses() async {
    try {
      final result = await ApiService.getAdminCampuses(token: widget.token);
      setState(() {
        _campuses = result['campuses'] ?? [];
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Campus Management')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final added = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => AdminAddCampusScreen(token: widget.token),
            ),
          );
          if (added == true) {
            _loadCampuses();
          }
        },
        backgroundColor: const Color(0xFF005A23),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(child: Text(_error))
          : _campuses.isEmpty
          ? const Center(child: Text('No campuses found.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _campuses.length,
              itemBuilder: (context, index) {
                final campus = _campuses[index];
                return GestureDetector(
                  onTap: () async {
                    final updated = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdminCampusDetailScreen(
                          campus: campus,
                          token: widget.token,
                        ),
                      ),
                    );
                    if (updated == true) {
                      _loadCampuses();
                    }
                  },
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF005A23,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.location_city,
                              color: Color(0xFF005A23),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  campus['campus_name'] ?? '--',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Code: ${campus['campus_code'] ?? '--'}',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Tap to view boundary map',
                                  style: TextStyle(
                                    color: Color(0xFF005A23),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

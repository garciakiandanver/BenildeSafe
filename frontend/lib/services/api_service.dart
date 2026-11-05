import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'device_service.dart';

class ApiService {
  static String get baseUrl => kReleaseMode
      ? 'https://benildesafe-api.vercel.app/api'
      : 'http://192.168.1.165:3000/api';

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'device_id': await DeviceService.getId(),
      }),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> requestPasswordReset({
    required String email,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code, 'password': password}),
    );
    return _handleResponse(response);
  }

  // Signed-in users change their own password (needs the current password).
  static Future<Map<String, dynamic>> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/change-password'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> checkIn({
    required String token,
    required double latitude,
    required double longitude,
    double? accuracy,
    bool? isMocked,
    // True when the app times the student in by itself. The server then answers
    // quietly (auto_skipped) when the student is not inside the campus.
    bool auto = false,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/check-in'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        // How accurate the GPS reading is, in meters. The server uses it to
        // avoid wrong inside / outside results near the campus boundary.
        'accuracy': ?accuracy,
        if (isMocked == true) 'is_mocked': true,
        if (auto) 'auto': true,
      }),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> detectCampus({
    required String token,
    required double latitude,
    required double longitude,
    double? accuracy,
    bool? isMocked,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/detect-campus'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        // How accurate the GPS reading is, in meters. The server uses it to
        // avoid wrong inside / outside results near the campus boundary.
        'accuracy': ?accuracy,
        if (isMocked == true) 'is_mocked': true,
      }),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getActiveAttendance({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/attendance/active'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    return _handleResponse(response);
  }

  // Teacher portal: the courses and year levels that have students.
  static Future<Map<String, dynamic>> getTeacherFilters({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/teacher/filters'),
      headers: _authenticatedJsonHeaders(token),
    );
    return _handleResponse(response);
  }

  // Teacher portal: the daily time record of every student of one course and
  // year level for one month. month is 'YYYY-MM'.
  static Future<Map<String, dynamic>> getTeacherStudentsDtr({
    required String token,
    required String course,
    required String yearLevel,
    required String month,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/teacher/students-dtr').replace(
        queryParameters: {
          'course': course,
          'year_level': yearLevel,
          'month': month,
        },
      ),
      headers: _authenticatedJsonHeaders(token),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getAttendanceHistory({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/attendance/history'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> updateLocation({
    required String token,
    required double latitude,
    required double longitude,
    double? accuracy,
    bool? isMocked,
    // false: the server may ask for a second reading before it records that
    // the student left the campus. true: this is that second reading.
    bool? confirmed,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/location'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        // How accurate the GPS reading is, in meters. The server uses it to
        // avoid wrong inside / outside results near the campus boundary.
        'accuracy': ?accuracy,
        if (isMocked == true) 'is_mocked': true,
        'confirmed': ?confirmed,
      }),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> checkOut({
    required String token,
    required double latitude,
    required double longitude,
    double? accuracy,
    bool? isMocked,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/check-out'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        // How accurate the GPS reading is, in meters. The server uses it to
        // avoid wrong inside / outside results near the campus boundary.
        'accuracy': ?accuracy,
        if (isMocked == true) 'is_mocked': true,
      }),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getChildren({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/parent/children'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getChildAttendance({
    required String token,
    required String studentId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/parent/children/$studentId/attendance'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getAdminSummary({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/summary'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getAdminStudents({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/students'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  // Adds one teacher account. The server makes a temporary password and emails
  // it; the teacher is asked to change it at the first sign-in.
  static Future<Map<String, dynamic>> addTeacher({
    required String token,
    required String firstName,
    required String middleName,
    required String lastName,
    required String email,
    required String employeeNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/teachers'),
      headers: _authenticatedJsonHeaders(token),
      body: jsonEncode({
        'first_name': firstName,
        'middle_name': middleName,
        'last_name': lastName,
        'email': email,
        'employee_number': employeeNumber,
      }),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getAdminTeachers({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/teachers'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getAdminParents({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/parents'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> linkParentChild({
    required String token,
    required String parentId,
    required String studentNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/parents/$parentId/children'),
      headers: _authenticatedJsonHeaders(token),
      body: jsonEncode({'student_number': studentNumber}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> unlinkParentChild({
    required String token,
    required String parentId,
    required String studentId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/parents/$parentId/children/$studentId'),
      headers: _authenticatedJsonHeaders(token),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> updateManagedUser({
    required String token,
    required String userId,
    required Map<String, dynamic> user,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/admin/users/$userId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(user),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> setManagedUserStatus({
    required String token,
    required String userId,
    required String status,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/users/$userId/status'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'status': status}),
    );
    return _handleResponse(response);
  }

  /// Unlinks a student account from its phone so it can be used on a new one.
  static Future<Map<String, dynamic>> resetStudentDevice({
    required String token,
    required String userId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/users/$userId/device'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  // ---- Optional daily photo verification (student) ----

  static Future<Map<String, dynamic>> getTodayPhotoStatus({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/attendance/photo/today'),
      headers: _authenticatedJsonHeaders(token),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> startPhotoVerification({
    required String token,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/photo/start'),
      headers: _authenticatedJsonHeaders(token),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> submitPhotoVerification({
    required String token,
    required String startToken,
    required String photoBase64,
    required double latitude,
    required double longitude,
    required double accuracy,
    required bool isMocked,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/photo'),
      headers: _authenticatedJsonHeaders(token),
      body: jsonEncode({
        'start_token': startToken,
        'photo': photoBase64,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'is_mocked': isMocked,
      }),
    );
    return _handleResponse(response);
  }

  // ---- Verification photos (administrator) ----

  static Future<Map<String, dynamic>> getAdminPhotos({
    required String token,
    required String date,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/photos?date=$date'),
      headers: _authenticatedJsonHeaders(token),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getAdminPhoto({
    required String token,
    required String userId,
    required String date,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/photos/$userId/$date'),
      headers: _authenticatedJsonHeaders(token),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getAdminCampuses({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/campuses'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getCourses({
    required String token,
    String? termId,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/admin/class-schedules/courses',
    ).replace(queryParameters: termId == null ? null : {'termId': termId});
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> addCourse({
    required String token,
    required String courseCode,
    required String courseName,
    String? departmentId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/class-schedules/courses'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'course_code': courseCode,
        'course_name': courseName,
        'department_id': departmentId,
      }),
    );
    return _handleResponse(response);
  }

  // The course code cannot be changed; only the name and department can.
  static Future<Map<String, dynamic>> updateCourse({
    required String token,
    required String courseCode,
    required String courseName,
    String? departmentId,
  }) async {
    final response = await http.put(
      Uri.parse(
        '$baseUrl/admin/class-schedules/courses/${Uri.encodeComponent(courseCode)}',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'course_name': courseName,
        'department_id': departmentId,
      }),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> deleteCourse({
    required String token,
    required String courseCode,
  }) async {
    final response = await http.delete(
      Uri.parse(
        '$baseUrl/admin/class-schedules/courses/${Uri.encodeComponent(courseCode)}',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getDepartments({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/class-schedules/departments'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> addDepartment({
    required String token,
    required String departmentCode,
    required String departmentName,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/class-schedules/departments'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'department_code': departmentCode,
        'department_name': departmentName,
      }),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> updateDepartment({
    required String token,
    required String departmentId,
    required String departmentCode,
    required String departmentName,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/admin/class-schedules/departments/$departmentId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'department_code': departmentCode,
        'department_name': departmentName,
      }),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> deleteDepartment({
    required String token,
    required String departmentId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/class-schedules/departments/$departmentId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getNotifications({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/notifications'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> markNotificationRead({
    required String token,
    required String notificationId,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/notifications/$notificationId/read'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> markAllNotificationsRead({
    required String token,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/notifications/read-all'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> updateCampusBoundary({
    required String token,
    required String campusId,
    required List<List<double>> coordinates,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/admin/campuses/$campusId/boundary'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'coordinates': coordinates}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> addCampus({
    required String token,
    required String campusName,
    required String campusCode,
    required double latitude,
    required double longitude,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/campuses'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'campus_name': campusName,
        'campus_code': campusCode,
        'latitude': latitude,
        'longitude': longitude,
      }),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> deleteCampus({
    required String token,
    required String campusId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/campuses/$campusId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  // Students only; the server no longer takes a role. Course and year level
  // come back with every record and are filtered in the screen itself.
  static Future<Map<String, dynamic>> getAdminAttendance({
    required String token,
    String? date,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/admin/attendance',
    ).replace(queryParameters: {'date': ?date});

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }


  // Admin: students on campus each day for the last [days] Manila days (7 or
  // 30), with how many were late. For the dashboard chart.
  static Future<Map<String, dynamic>> getAttendanceTrend({
    required String token,
    int days = 7,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/admin/attendance/trend',
    ).replace(queryParameters: {'days': '$days'});

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  // ---------------------------------------------------------------- child links

  // Parent: ask to link another child by student number (the admin approves).
  static Future<Map<String, dynamic>> requestChildLink({
    required String token,
    required String studentNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/child-links'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'student_number': studentNumber}),
    );
    return _handleResponse(response);
  }

  // Parent: my own link requests and their status.
  static Future<Map<String, dynamic>> getMyChildLinkRequests({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/child-links/mine'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  // Admin: every child link request.
  static Future<Map<String, dynamic>> getChildLinkRequests({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/child-links'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> approveChildLink({
    required String token,
    required String requestId,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/child-links/$requestId/approve'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> rejectChildLink({
    required String token,
    required String requestId,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/child-links/$requestId/reject'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }




  static Future<Map<String, dynamic>> correctAttendance({
    required String token,
    required String attendanceId,
    String? timeIn,
    String? timeOut,
    String? status,
    required String remarks,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/admin/attendance/$attendanceId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'time_in': ?timeIn,
        'time_out': ?timeOut,
        'status': ?status,
        'remarks': remarks,
      }),
    );
    return _handleResponse(response);
  }

  // Students only, with course and year level on every row.
  static Future<Map<String, dynamic>> getReportUsers({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/report/users');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getUserAttendanceReport({
    required String token,
    required String userId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/report/users/$userId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  // ---------------------------------------------------------------- profile

  static Future<Map<String, dynamic>> getProfile({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/profile'),
      headers: _authenticatedJsonHeaders(token),
    );
    return _handleResponse(response);
  }

  // photo is a data URL, e.g. "data:image/jpeg;base64,...."
  static Future<Map<String, dynamic>> uploadProfilePhoto({
    required String token,
    required String photo,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/profile/photo'),
      headers: _authenticatedJsonHeaders(token),
      body: jsonEncode({'photo': photo}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> deleteProfilePhoto({
    required String token,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/profile/photo'),
      headers: _authenticatedJsonHeaders(token),
    );
    return _handleResponse(response);
  }

  // ------------------------------------------------------------ bulk accounts

  // Reads and checks an Excel / CSV file of students and parents.
  // Nothing is created yet.
  static Future<Map<String, dynamic>> previewBulkAccounts({
    required String token,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final accessToken = token.trim();
    if (accessToken.isEmpty) {
      throw Exception('Your session has expired. Please sign in again.');
    }
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('$baseUrl/admin/bulk-accounts/preview'),
          )
          ..headers['Authorization'] = 'Bearer $accessToken'
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: fileName),
          );
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return _handleResponse(response);
  }

  // Creates the accounts of a few checked rows and emails them.
  static Future<Map<String, dynamic>> commitBulkAccounts({
    required String token,
    required List<Map<String, dynamic>> rows,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/bulk-accounts/commit'),
      headers: _authenticatedJsonHeaders(token),
      body: jsonEncode({'rows': rows}),
    );
    return _handleResponse(response);
  }

  // Accounts that still have a temporary password.
  static Future<Map<String, dynamic>> getPendingAccounts({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/bulk-accounts/pending'),
      headers: _authenticatedJsonHeaders(token),
    );
    return _handleResponse(response);
  }

  // Emails a NEW temporary password to accounts that have not signed in yet.
  static Future<Map<String, dynamic>> resendAccountEmails({
    required String token,
    required List<String> emails,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/bulk-accounts/resend'),
      headers: _authenticatedJsonHeaders(token),
      body: jsonEncode({'emails': emails}),
    );
    return _handleResponse(response);
  }

  static Map<String, dynamic> _handleResponse(http.Response response) {
    final data = jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw Exception(data['message'] ?? 'Request failed.');
  }

  static Map<String, String> _authenticatedJsonHeaders(String token) {
    final accessToken = token.trim();
    if (accessToken.isEmpty) {
      throw Exception('Your session has expired. Please sign in again.');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
    };
  }
}
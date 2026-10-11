import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kReleaseMode;

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
      body: jsonEncode({'email': email, 'password': password}),
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
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/check-in'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> detectCampus({
    required String token,
    required double latitude,
    required double longitude,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/detect-campus'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
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

  static Future<Map<String, dynamic>> getCurrentClassSchedule({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/attendance/current-class'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getMyClassSchedule({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/attendance/my-schedule'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  // Teacher portal: attendance of every student in one of the teacher's classes.
  // period is 'daily', 'weekly' or 'monthly'; date is 'YYYY-MM-DD'.
  static Future<Map<String, dynamic>> getTeacherClassAttendance({
    required String token,
    required String scheduleId,
    required String period,
    required String date,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/teacher/class-attendance').replace(
        queryParameters: {
          'schedule_id': scheduleId,
          'period': period,
          'date': date,
        },
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
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
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/location'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> checkOut({
    required String token,
    required double latitude,
    required double longitude,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/check-out'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
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

  static Future<Map<String, dynamic>> getClassSchedules({
    required String token,
    String? courseCode,
    String? termId,
  }) async {
    final path = courseCode == null
        ? '$baseUrl/admin/class-schedules'
        : '$baseUrl/admin/class-schedules/${Uri.encodeComponent(courseCode)}/schedules';
    final uri = Uri.parse(
      path,
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

  static Future<Map<String, dynamic>> getAcademicTerms({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/class-schedules/terms'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> createAcademicTerm({
    required String token,
    required String schoolYear,
    required String semester,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/class-schedules/terms'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'school_year': schoolYear, 'semester': semester}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> updateAcademicTerm({
    required String token,
    required String termId,
    required String schoolYear,
    required String semester,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/admin/class-schedules/terms/$termId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'school_year': schoolYear, 'semester': semester}),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> archiveCourseTermSchedules({
    required String token,
    required String courseCode,
    required String termId,
  }) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/admin/class-schedules/${Uri.encodeComponent(courseCode)}/archive',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'term_id': termId}),
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

  static Future<Map<String, dynamic>> updateClassSchedule({
    required String token,
    required String scheduleId,
    required Map<String, dynamic> schedule,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/admin/class-schedules/$scheduleId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(schedule),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> deleteClassSchedule({
    required String token,
    required String scheduleId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/class-schedules/$scheduleId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> importClassSchedules({
    required String token,
    required String fileName,
    required Uint8List bytes,
    required int lateAfterMinutes,
    // null = whole-school upload: each row names its own course.
    String? courseCode,
    required String campusCode,
  }) async {
    final path = courseCode == null
        ? '$baseUrl/admin/class-schedules/import'
        : '$baseUrl/admin/class-schedules/${Uri.encodeComponent(courseCode)}/import';
    final request =
        http.MultipartRequest('POST', Uri.parse(path))
          ..headers['Authorization'] = 'Bearer $token'
          ..fields['late_after_minutes'] = lateAfterMinutes.toString()
          ..fields['campus_code'] = campusCode
          ..files.add(
            http.MultipartFile.fromBytes('schedule', bytes, filename: fileName),
          );
    if (courseCode != null) {
      request.fields['course_code'] = courseCode;
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
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

  static Future<Map<String, dynamic>> getAdminAttendance({
    required String token,
    String? date,
    String? role,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/admin/attendance',
    ).replace(queryParameters: {'date': ?date, 'role': ?role});

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String firstName,
    required String middleName,
    required String lastName,
    required int requestedRoleId,
    String? studentNumber,
    String? course,
    String? yearLevel,
    String? section,
    String? employeeNumber,
    String? contactNumber,
    String? childStudentNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'first_name': firstName,
        'middle_name': middleName,
        'last_name': lastName,
        'requested_role_id': requestedRoleId,
        'student_number': studentNumber,
        'course': course,
        'year_level': yearLevel,
        'section': section,
        'employee_number': employeeNumber,
        'contact_number': contactNumber,
        'child_student_number': childStudentNumber,
      }),
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

  static Future<Map<String, dynamic>> getRegistrationRequests({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/registration-requests'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> approveRequest({
    required String token,
    required String requestId,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/admin/registration-requests/$requestId/approve'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> rejectRequest({
    required String token,
    required String requestId,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/admin/registration-requests/$requestId/reject'),
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
      }),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getReportUsers({
    required String token,
    String? role,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/admin/report/users',
    ).replace(queryParameters: role == null ? null : {'role': role});
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
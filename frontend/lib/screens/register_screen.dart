import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  // Student fields
  final _studentNumberController = TextEditingController();
  final _courseController = TextEditingController();
  final _yearLevelController = TextEditingController();
  final _sectionController = TextEditingController();

  // Teacher fields
  final _employeeNumberController = TextEditingController();

  // Parent fields
  final _contactNumberController = TextEditingController();
  final _childStudentNumberController = TextEditingController();

  int? _selectedRoleId;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSuccess = false;
  bool _autoValidate = false;

  final List<Map<String, dynamic>> _roles = [
    {'id': 2, 'name': 'Student', 'icon': Icons.school},
    {'id': 3, 'name': 'Teacher', 'icon': Icons.person},
    {'id': 4, 'name': 'Parent', 'icon': Icons.family_restroom},
  ];

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _studentNumberController.dispose();
    _courseController.dispose();
    _yearLevelController.dispose();
    _sectionController.dispose();
    _employeeNumberController.dispose();
    _contactNumberController.dispose();
    _childStudentNumberController.dispose();
    super.dispose();
  }

  // ── Validators ───────────────────────────────────────────────────

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required.';
    final emailRegex = RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required.';
    if (value.length < 8) return 'Password must be at least 8 characters.';
    if (!value.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter.';
    }
    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number.';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) return 'Please confirm your password.';
    if (value != _passwordController.text) return 'Passwords do not match.';
    return null;
  }

  String? _validateName(
    String? value,
    String fieldName, {
    bool required = true,
  }) {
    if (value == null || value.trim().isEmpty) {
      return required ? '$fieldName is required.' : null;
    }
    if (value.contains(RegExp(r'[0-9]'))) {
      return '$fieldName must not contain numbers.';
    }
    if (value.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'))) {
      return '$fieldName must not contain special characters.';
    }
    return null;
  }

  String? _validateStudentNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Student number is required.';
    }
    final regex = RegExp(r'^[A-Za-z]+-\d{4}-\d{2}-\d{5}$');
    if (!regex.hasMatch(value.trim())) {
      return 'Format must be COURSE-YYYY-BB-XXXXX (e.g. BSIT-2023-01-00062).';
    }
    return null;
  }

  String? _validateEmployeeNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Employee number is required.';
    }
    final regex = RegExp(r'^T-\d{4}-\d{3}$');
    if (!regex.hasMatch(value.trim())) {
      return 'Format must be T-YYYY-XXX (e.g. T-2026-001).';
    }
    return null;
  }

  String? _validateContactNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Contact number is required.';
    }
    final regex = RegExp(r'^09\d{9}$');
    if (!regex.hasMatch(value.trim())) {
      return 'Must be 11 digits starting with 09.';
    }
    return null;
  }

  String? _validateYearLevel(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Year level is required.';
    }
    final level = int.tryParse(value.trim());
    if (level == null || level < 1 || level > 4) {
      return 'Year level must be between 1 and 4.';
    }
    return null;
  }

  String? _validateSection(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional
    final regex = RegExp(r'^[A-Za-z]$');
    if (!regex.hasMatch(value.trim())) {
      return 'Section must be a single letter (A-Z).';
    }
    return null;
  }

  String? _validateCourse(String? value) {
    if (value == null || value.trim().isEmpty) return 'Course is required.';
    if (value.contains(RegExp(r'[0-9!@#\$%^&*(),.?":{}|<>]'))) {
      return 'Course must not contain numbers or special characters.';
    }
    return null;
  }

  // ── Submit ───────────────────────────────────────────────────────

  Future<void> _submit() async {
    setState(() {
      _autoValidate = true;
    });

    if (_selectedRoleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a role.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await ApiService.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        firstName: _firstNameController.text.trim(),
        middleName: _middleNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        requestedRoleId: _selectedRoleId!,
        studentNumber: _selectedRoleId == 2
            ? _studentNumberController.text.trim()
            : null,
        course: _selectedRoleId == 2 ? _courseController.text.trim() : null,
        yearLevel: _selectedRoleId == 2
            ? _yearLevelController.text.trim()
            : null,
        section:
            _selectedRoleId == 2 && _sectionController.text.trim().isNotEmpty
            ? _sectionController.text.trim()
            : null,
        employeeNumber: _selectedRoleId == 3
            ? _employeeNumberController.text.trim()
            : null,
        contactNumber: _selectedRoleId == 4
            ? _contactNumberController.text.trim()
            : null,
        childStudentNumber: _selectedRoleId == 4
            ? _childStudentNumberController.text.trim()
            : null,
      );

      setState(() {
        _isSuccess = true;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ── UI Helpers ───────────────────────────────────────────────────

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    bool required = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        autovalidateMode: _autoValidate
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        validator: validator,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint,
          border: const OutlineInputBorder(),
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }

  Widget _buildRoleSpecificFields() {
    if (_selectedRoleId == 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Student Information',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF005A23),
              ),
            ),
          ),
          _buildFormField(
            controller: _studentNumberController,
            label: 'Student Number',
            hint: 'e.g. BSIT-2023-01-00001',
            validator: _validateStudentNumber,
          ),
          _buildFormField(
            controller: _courseController,
            label: 'Course',
            hint: 'e.g. BSIT',
            validator: _validateCourse,
          ),
          _buildFormField(
            controller: _yearLevelController,
            label: 'Year Level',
            hint: 'e.g. 3',
            keyboardType: TextInputType.number,
            validator: _validateYearLevel,
          ),
          _buildFormField(
            controller: _sectionController,
            label: 'Section',
            hint: 'e.g. A (optional)',
            required: false,
            validator: _validateSection,
          ),
        ],
      );
    } else if (_selectedRoleId == 3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Teacher Information',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF005A23),
              ),
            ),
          ),
          _buildFormField(
            controller: _employeeNumberController,
            label: 'Employee Number',
            hint: 'e.g. T-2026-001',
            validator: _validateEmployeeNumber,
          ),
        ],
      );
    } else if (_selectedRoleId == 4) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Parent Information',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF005A23),
              ),
            ),
          ),
          _buildFormField(
            controller: _contactNumberController,
            label: 'Contact Number',
            hint: 'e.g. 09171234567',
            keyboardType: TextInputType.phone,
            validator: _validateContactNumber,
          ),
          _buildFormField(
            controller: _childStudentNumberController,
            label: "Child's Student Number",
            hint: 'e.g. BSIT-2023-01-00001',
            required: true,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return "Child's student number is required.";
              }
              final regex = RegExp(r'^[A-Za-z]+-\d{4}-\d{2}-\d{5}$');
              if (!regex.hasMatch(value.trim())) {
                return "Format must be COURSE-YYYY-BB-XXXXX (e.g. BSIT-2023-01-00001).";
              }
              return null;
            },
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _isSuccess
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Registration Submitted!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Your registration request has been submitted successfully. An email will be sent to you when an administrator approves or declines it.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.green),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Back to Login'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Step 1: Select Role
                    const Text(
                      'Step 1: Select Your Role',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: _roles.map((role) {
                        final isSelected = _selectedRoleId == role['id'];
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedRoleId = role['id'];
                                  _autoValidate = false;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF005A23)
                                      : Colors.grey.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF005A23)
                                        : Colors.grey,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      role['icon'] as IconData,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.grey,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      role['name'],
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.grey,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    if (_selectedRoleId != null) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Step 2: Fill in Your Information',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '* Required fields',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 16),

                      _buildFormField(
                        controller: _firstNameController,
                        label: 'First Name',
                        validator: (v) => _validateName(v, 'First name'),
                      ),
                      _buildFormField(
                        controller: _middleNameController,
                        label: 'Middle Name',
                        required: false,
                        validator: (v) =>
                            _validateName(v, 'Middle name', required: false),
                      ),
                      _buildFormField(
                        controller: _lastNameController,
                        label: 'Last Name',
                        validator: (v) => _validateName(v, 'Last name'),
                      ),
                      _buildFormField(
                        controller: _emailController,
                        label: 'Email',
                        keyboardType: TextInputType.emailAddress,
                        validator: _validateEmail,
                      ),
                      _buildFormField(
                        controller: _passwordController,
                        label: 'Password',
                        hint: 'Min 8 chars, 1 uppercase, 1 number',
                        obscureText: _obscurePassword,
                        validator: _validatePassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      _buildFormField(
                        controller: _confirmPasswordController,
                        label: 'Confirm Password',
                        obscureText: _obscureConfirmPassword,
                        validator: _validateConfirmPassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                        ),
                      ),

                      _buildRoleSpecificFields(),

                      const SizedBox(height: 16),

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
                                'SUBMIT REGISTRATION',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

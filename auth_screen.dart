import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'health_dashboard.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  bool obscurePassword = true;
  bool isLoading = false;

  final _formKey = GlobalKey<FormState>();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final nameController = TextEditingController();
  final ageController = TextEditingController();
  final heightController = TextEditingController();
  final weightController = TextEditingController();
  final diseaseController = TextEditingController();

  String selectedGender = 'Male';

  Future<void> handleAuth() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();

    if (isLogin) {
      final savedEmail = prefs.getString('email');
      final savedPassword = prefs.getString('password');

      if (emailController.text.trim() == savedEmail &&
          passwordController.text.trim() == savedPassword) {
        await prefs.setBool('isLoggedIn', true);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HealthDashboard()),
        );
      } else {
        showMsg('Invalid email or password');
      }
    } else {
      await prefs.setString('name', nameController.text.trim());
      await prefs.setString('age', ageController.text.trim());
      await prefs.setString('height', heightController.text.trim());
      await prefs.setString('weight', weightController.text.trim());
      await prefs.setString('gender', selectedGender);
      await prefs.setString('disease', diseaseController.text.trim());
      await prefs.setString('email', emailController.text.trim());
      await prefs.setString('password', passwordController.text.trim());
      await prefs.setBool('isLoggedIn', true);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HealthDashboard()),
      );
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  void showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  InputDecoration inputDecoration({
    required String label,
    IconData? icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon:
          icon != null ? Icon(icon, color: const Color(0xFF6B7A99)) : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF7FAFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE7EEF8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF3366FF), width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
      labelStyle: const TextStyle(
        color: Color(0xFF718096),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: isPassword ? obscurePassword : false,
        maxLines: maxLines,
        validator: validator,
        decoration: inputDecoration(
          label: label,
          icon: icon,
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: const Color(0xFF6B7A99),
                  ),
                  onPressed: () {
                    setState(() {
                      obscurePassword = !obscurePassword;
                    });
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget buildGenderSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: selectedGender,
        decoration: inputDecoration(
          label: 'Gender',
          icon: Icons.person_outline,
        ),
        items: const [
          DropdownMenuItem(value: 'Male', child: Text('Male')),
          DropdownMenuItem(value: 'Female', child: Text('Female')),
          DropdownMenuItem(value: 'Other', child: Text('Other')),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            selectedGender = value;
          });
        },
      ),
    );
  }

  String? requiredValidator(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter $fieldName';
    }
    return null;
  }

  String? emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter email';
    }
    if (!value.contains('@') || !value.contains('.')) {
      return 'Enter a valid email';
    }
    return null;
  }

  String? passwordValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter password';
    }
    if (value.trim().length < 4) {
      return 'Password must be at least 4 characters';
    }
    return null;
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    ageController.dispose();
    heightController.dispose();
    weightController.dispose();
    diseaseController.dispose();
    super.dispose();
  }

  Widget buildHeader() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFEAF1FF), Color(0xFFDCE8FF)],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(
            Icons.monitor_heart_outlined,
            color: Color(0xFF3366FF),
            size: 36,
          ),
        ),
        const SizedBox(height: 18),
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
            children: [
              TextSpan(
                text: 'Ok',
                style: TextStyle(color: Color(0xFF1F2A44)),
              ),
              TextSpan(
                text: 'Health',
                style: TextStyle(color: Color(0xFF3366FF)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isLogin
              ? 'Login to continue your health monitoring'
              : 'Create your health profile to get started',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF7C8BA1),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF3C4B68),
          ),
        ),
      ),
    );
  }

  Widget buildAuthCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 430),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(34),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.06),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildHeader(),
            const SizedBox(height: 26),

            if (!isLogin) ...[
              buildSectionTitle('Personal Details'),
              buildTextField(
                label: 'Full Name',
                controller: nameController,
                icon: Icons.badge_outlined,
                validator: (value) => requiredValidator(value, 'full name'),
              ),
              buildTextField(
                label: 'Age',
                controller: ageController,
                icon: Icons.cake_outlined,
                keyboardType: TextInputType.number,
                validator: (value) => requiredValidator(value, 'age'),
              ),
              buildTextField(
                label: 'Height (cm)',
                controller: heightController,
                icon: Icons.height,
                keyboardType: TextInputType.number,
                validator: (value) => requiredValidator(value, 'height'),
              ),
              buildTextField(
                label: 'Weight (kg)',
                controller: weightController,
                icon: Icons.monitor_weight_outlined,
                keyboardType: TextInputType.number,
                validator: (value) => requiredValidator(value, 'weight'),
              ),
              buildGenderSelector(),
              buildTextField(
                label: 'Disease / Medical Condition',
                controller: diseaseController,
                icon: Icons.medical_information_outlined,
                validator: (_) => null,
              ),
              const SizedBox(height: 4),
              buildSectionTitle('Account Details'),
            ],

            buildTextField(
              label: 'Email',
              controller: emailController,
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: emailValidator,
            ),
            buildTextField(
              label: 'Password',
              controller: passwordController,
              icon: Icons.lock_outline,
              isPassword: true,
              validator: passwordValidator,
            ),

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: isLoading ? null : handleAuth,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3366FF),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        isLogin ? 'Login' : 'Register',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isLogin
                      ? "Don't have an account?"
                      : "Already have an account?",
                  style: const TextStyle(
                    color: Color(0xFF7C8BA1),
                    fontSize: 14,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      isLogin = !isLogin;
                    });
                  },
                  child: Text(
                    isLogin ? 'Register' : 'Login',
                    style: const TextStyle(
                      color: Color(0xFF3366FF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: buildAuthCard(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ble_service.dart';
import 'auth_screen.dart';

class HealthDashboard extends StatefulWidget {
  const HealthDashboard({super.key});

  @override
  State<HealthDashboard> createState() => _HealthDashboardState();
}

class _HealthDashboardState extends State<HealthDashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final BleService bleService = BleService();

  StreamSubscription<String>? _bleSubscription;

  int heartRate = 0;
  int spo2 = 0;
  double temperature = 0.0;
  String connectionStatus = 'Disconnected';
  DateTime? lastUpdated;
  bool isConnecting = false;
  bool hasActiveReading = false;

  String name = '';
  String age = '';
  String height = '';
  String weight = '';
  String gender = '';
  String disease = '';

  int selectedIndex = 0;
  int selectedHistoryFilter = 0;

  final List<String> _historyFilters = ['Day', 'Week', 'Month', 'Year'];

  List<Map<String, String>> emergencyContacts = [];
  final TextEditingController contactNameController = TextEditingController();
  final TextEditingController contactPhoneController = TextEditingController();

  List<Map<String, dynamic>> historyData = [];
  DateTime? lastHistorySavedAt;

  @override
  void initState() {
    super.initState();
    loadUserData();
    loadEmergencyContacts();
    loadHistory();
    _listenToBleStream();
  }

  @override
  void dispose() {
    _bleSubscription?.cancel();
    contactNameController.dispose();
    contactPhoneController.dispose();
    super.dispose();
  }

  void _listenToBleStream() {
    _bleSubscription?.cancel();
    _bleSubscription = bleService.dataStream.listen(
      (data) {
        debugPrint('BLE RAW DATA: $data');
        _parseIncomingData(data);
      },
      onError: (error) {
        debugPrint('BLE Stream Error: $error');
        if (!mounted) return;
        setState(() {
          connectionStatus = hasActiveReading ? 'Connected' : 'Disconnected';
          isConnecting = false;
        });
      },
      onDone: () {
        debugPrint('BLE stream closed');
        if (!mounted) return;
        setState(() {
          connectionStatus = hasActiveReading ? 'Connected' : 'Disconnected';
          isConnecting = false;
        });
      },
      cancelOnError: false,
    );
  }

  void _parseIncomingData(String data) {
    try {
      final cleaned = data.replaceAll('\n', '').replaceAll('\r', '').trim();
      if (cleaned.isEmpty) return;

      final parts = cleaned.split(',');
      if (parts.length < 3) return;

      final parsedHeartRate = int.tryParse(parts[0].trim()) ?? heartRate;
      final parsedSpo2 = int.tryParse(parts[1].trim()) ?? spo2;
      final parsedTemperature =
          double.tryParse(parts[2].trim()) ?? temperature;

      if (!mounted) return;

      setState(() {
        heartRate = parsedHeartRate;
        spo2 = parsedSpo2;
        temperature = parsedTemperature;
        lastUpdated = DateTime.now();
        isConnecting = false;
        hasActiveReading =
            parsedHeartRate > 0 || parsedSpo2 > 0 || parsedTemperature > 0;
        connectionStatus = hasActiveReading ? 'Connected' : 'Measuring';
      });

      _saveHistoryIfNeeded();
    } catch (e) {
      debugPrint('Parse Error: $e');
    }
  }

  Future<void> loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      name = prefs.getString('name') ?? 'Hritik Patel';
      age = prefs.getString('age') ?? '20';
      height = prefs.getString('height') ?? '180';
      weight = prefs.getString('weight') ?? '65';
      gender = prefs.getString('gender') ?? 'Male';
      disease = prefs.getString('disease') ?? 'None';
    });
  }

  Future<void> loadEmergencyContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final savedList = prefs.getStringList('emergency_contacts') ?? [];

    final loadedContacts = savedList.map((item) {
      final decoded = jsonDecode(item) as Map<String, dynamic>;
      return {
        'name': (decoded['name'] ?? '').toString(),
        'phone': (decoded['phone'] ?? '').toString(),
      };
    }).toList();

    if (!mounted) return;

    setState(() {
      emergencyContacts = loadedContacts;
    });
  }

  Future<void> saveEmergencyContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedList = emergencyContacts.map((contact) {
      return jsonEncode({
        'name': contact['name'] ?? '',
        'phone': contact['phone'] ?? '',
      });
    }).toList();

    await prefs.setStringList('emergency_contacts', encodedList);
  }

  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('history') ?? [];

    final loadedHistory = list.map((item) {
      return Map<String, dynamic>.from(jsonDecode(item));
    }).toList();

    if (!mounted) return;

    setState(() {
      historyData = loadedHistory;
    });
  }

  Future<void> saveHistory() async {
    final prefs = await SharedPreferences.getInstance();

    final entry = {
      'hr': heartRate,
      'spo2': spo2,
      'temp': temperature,
      'time': DateTime.now().toIso8601String(),
    };

    historyData.add(entry);

    if (historyData.length > 150) {
      historyData = historyData.sublist(historyData.length - 150);
    }

    final encodedList = historyData.map((item) => jsonEncode(item)).toList();
    await prefs.setStringList('history', encodedList);
  }

  Future<void> _saveHistoryIfNeeded() async {
    if (!hasActiveReading) return;
    if (heartRate <= 0 && spo2 <= 0 && temperature <= 0) return;

    final now = DateTime.now();
    if (lastHistorySavedAt != null &&
        now.difference(lastHistorySavedAt!).inSeconds < 10) {
      return;
    }

    lastHistorySavedAt = now;
    await saveHistory();

    if (mounted) {
      setState(() {});
    }
  }

  void addEmergencyContact() {
    final contactName = contactNameController.text.trim();
    final contactPhone = contactPhoneController.text.trim();

    if (contactName.isEmpty || contactPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter name and phone number')),
      );
      return;
    }

    if (emergencyContacts.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can add only up to 3 contacts')),
      );
      return;
    }

    setState(() {
      emergencyContacts.add({
        'name': contactName,
        'phone': contactPhone,
      });
    });

    saveEmergencyContacts();
    contactNameController.clear();
    contactPhoneController.clear();

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Emergency contact added')),
    );
  }

  void removeEmergencyContact(int index) {
    setState(() {
      emergencyContacts.removeAt(index);
    });

    saveEmergencyContacts();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Emergency contact removed')),
    );
  }

  Future<void> sendEmergencyAlert() async {
    if (emergencyContacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one emergency contact'),
        ),
      );
      return;
    }

    final numbers =
        emergencyContacts.map((contact) => contact['phone'] ?? '').join(',');

    final message =
        'Emergency alert from OkHealth. '
        '${name.isEmpty ? "User" : name} may need help. '
        'Latest readings: HR $heartRate BPM, SpO2 $spo2%, Temp ${temperature.toStringAsFixed(1)} °C.';

    final Uri smsUri = Uri(
      scheme: 'sms',
      path: numbers,
      queryParameters: <String, String>{
        'body': message,
      },
    );

    try {
      final launched = await launchUrl(smsUri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open SMS app')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open SMS app: $e')),
      );
    }
  }

  void showAddContactDialog() {
    contactNameController.clear();
    contactPhoneController.clear();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Add Emergency Contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: contactNameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contactPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: addEmergencyContact,
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  bool _isHeartRateNormal() {
    if (heartRate == 0) return true;
    return heartRate >= 60 && heartRate <= 100;
  }

  bool _isSpo2Normal() {
    if (spo2 == 0) return true;
    return spo2 >= 95;
  }

  bool _isTemperatureNormal() {
    if (temperature == 0.0) return true;
    return temperature >= 33.5 && temperature <= 36.5;
  }

  bool isStable() {
    if (!hasActiveReading) return true;
    return _isHeartRateNormal() && _isSpo2Normal() && _isTemperatureNormal();
  }

  String getStatusText() {
    if (connectionStatus == 'Scanning...' || isConnecting) {
      return 'Connecting';
    }
    if (!hasActiveReading) {
      return connectionStatus == 'Connected' ? 'Measuring...' : '--';
    }
    return isStable() ? 'Normal' : 'Warning';
  }

  Color getStatusColor() {
    if (!hasActiveReading) {
      return const Color(0xFF94A3B8);
    }
    return isStable() ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
  }

  String getUpdatedText() {
    if (connectionStatus == 'Scanning...' || isConnecting) {
      return 'Searching for device';
    }
    if (!hasActiveReading || lastUpdated == null) {
      return connectionStatus == 'Connected'
          ? 'Waiting for live data'
          : 'Not connected';
    }

    final difference = DateTime.now().difference(lastUpdated!);
    if (difference.inSeconds < 5) return 'Updated just now';
    if (difference.inSeconds < 60) {
      return 'Updated ${difference.inSeconds}s ago';
    }
    return 'Updated ${difference.inMinutes}m ago';
  }

  List<_HealthAlertItem> _buildAlerts() {
    final alerts = <_HealthAlertItem>[];

    if (!hasActiveReading) {
      alerts.add(
        const _HealthAlertItem(
          title: 'No live health data yet',
          subtitle:
              'Connect OkHealth and place your finger properly to start readings.',
          color: Color(0xFF64748B),
          icon: Icons.sensors_off_rounded,
        ),
      );
      return alerts;
    }

    if (!_isHeartRateNormal()) {
      alerts.add(
        _HealthAlertItem(
          title: 'Heart rate needs attention',
          subtitle: 'Current heart rate is $heartRate BPM.',
          color: const Color(0xFFEF4444),
          icon: Icons.favorite_rounded,
        ),
      );
    }

    if (!_isSpo2Normal()) {
      alerts.add(
        _HealthAlertItem(
          title: 'Blood oxygen is below normal',
          subtitle: 'Current SpO₂ is $spo2%.',
          color: const Color(0xFF2563EB),
          icon: Icons.water_drop_rounded,
        ),
      );
    }

    if (!_isTemperatureNormal()) {
      alerts.add(
        _HealthAlertItem(
          title: 'Temperature is out of range',
          subtitle:
              'Current temperature is ${temperature.toStringAsFixed(1)} °C.',
          color: const Color(0xFFF59E0B),
          icon: Icons.thermostat_rounded,
        ),
      );
    }

    if (alerts.isEmpty) {
      alerts.add(
        const _HealthAlertItem(
          title: 'All readings are normal',
          subtitle:
              'Heart rate, SpO₂ and temperature are within a safe range.',
          color: Color(0xFF22C55E),
          icon: Icons.check_circle_rounded,
        ),
      );
    }

    return alerts;
  }

  Future<void> _showLogoutDialog() async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Logout'),
          content: const Text('Do you want to logout from the app?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                logout();
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _connectDevice() async {
    if (isConnecting) return;

    setState(() {
      connectionStatus = 'Scanning...';
      isConnecting = true;
    });

    try {
      await bleService.startScanAndConnect();

      if (!mounted) return;

      setState(() {
        connectionStatus = 'Connected';
        isConnecting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connected to OkHealth')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        connectionStatus = 'Disconnected';
        isConnecting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e')),
      );
    }
  }

  void _goToPage(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void showEditProfileDialog() {
    final nameController = TextEditingController(text: name);
    final ageController = TextEditingController(text: age);
    final heightController = TextEditingController(text: height);
    final weightController = TextEditingController(text: weight);
    final genderController = TextEditingController(text: gender);
    final diseaseController = TextEditingController(text: disease);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Edit Profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Age',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: genderController,
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: heightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Height (cm)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: weightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Weight (kg)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: diseaseController,
                  decoration: const InputDecoration(
                    labelText: 'Medical Issue / Disease',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();

                await prefs.setString('name', nameController.text.trim());
                await prefs.setString('age', ageController.text.trim());
                await prefs.setString('gender', genderController.text.trim());
                await prefs.setString('height', heightController.text.trim());
                await prefs.setString('weight', weightController.text.trim());
                await prefs.setString('disease', diseaseController.text.trim());

                if (!mounted) return;

                setState(() {
                  name = nameController.text.trim();
                  age = ageController.text.trim();
                  gender = genderController.text.trim();
                  height = heightController.text.trim();
                  weight = weightController.text.trim();
                  disease = diseaseController.text.trim().isEmpty
                      ? 'None'
                      : diseaseController.text.trim();
                });

                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile updated successfully')),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _filteredHistoryData() {
    final now = DateTime.now();

    return historyData.where((entry) {
      final timeString = entry['time']?.toString();
      if (timeString == null) return false;

      final time = DateTime.tryParse(timeString);
      if (time == null) return false;

      switch (selectedHistoryFilter) {
        case 0:
          return now.difference(time).inDays < 1;
        case 1:
          return now.difference(time).inDays < 7;
        case 2:
          return now.difference(time).inDays < 30;
        case 3:
          return now.difference(time).inDays < 365;
        default:
          return true;
      }
    }).toList();
  }

  double _averageHeartRate() {
    final filtered = _filteredHistoryData()
        .where((item) => (item['hr'] ?? 0) > 0)
        .toList();
    if (filtered.isEmpty) return 0;

    final total = filtered.fold<num>(0, (sum, item) => sum + (item['hr'] ?? 0));
    return total / filtered.length;
  }

  double _averageSpo2() {
    final filtered = _filteredHistoryData()
        .where((item) => (item['spo2'] ?? 0) > 0)
        .toList();
    if (filtered.isEmpty) return 0;

    final total =
        filtered.fold<num>(0, (sum, item) => sum + (item['spo2'] ?? 0));
    return total / filtered.length;
  }

  double _averageTemperature() {
    final filtered = _filteredHistoryData()
        .where((item) => ((item['temp'] ?? 0) as num) > 0)
        .toList();
    if (filtered.isEmpty) return 0;

    final total =
        filtered.fold<num>(0, (sum, item) => sum + ((item['temp'] ?? 0) as num));
    return total / filtered.length;
  }

  List<double> _historyHrPoints() {
    final filtered = _filteredHistoryData()
        .where((item) => (item['hr'] ?? 0) > 0)
        .toList();

    if (filtered.isEmpty) return [];

    final data = filtered.length > 12
        ? filtered.sublist(filtered.length - 12)
        : filtered;

    return data.map((e) => ((e['hr'] ?? 0) as num).toDouble()).toList();
  }

  String _formatHistoryTime(String timeString) {
    final parsed = DateTime.tryParse(timeString);
    if (parsed == null) return timeString;
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}  ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildCurrentPage() {
    switch (selectedIndex) {
      case 0:
        return _homePage();
      case 1:
        return _historyPage();
      case 2:
        return _alertsPage();
      case 3:
        return _profilePage();
      default:
        return _homePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      backgroundColor: const Color(0xFFF3F5F9),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Stack(
              children: [
                Positioned(
                  top: -80,
                  right: -60,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0FF),
                      borderRadius: BorderRadius.circular(110),
                    ),
                  ),
                ),
                Positioned(
                  top: 120,
                  left: -90,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F7FF),
                      borderRadius: BorderRadius.circular(90),
                    ),
                  ),
                ),
                Column(
                  children: [
                    Expanded(child: _buildCurrentPage()),
                    _bottomNav(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.favorite_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'OkHealth User' : name,
                          style: const TextStyle(
                            fontSize: 17,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          connectionStatus,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _drawerItem(
              icon: Icons.home_rounded,
              title: 'Home',
              onTap: () {
                Navigator.pop(context);
                _goToPage(0);
              },
            ),
            _drawerItem(
              icon: Icons.bar_chart_rounded,
              title: 'History',
              onTap: () {
                Navigator.pop(context);
                _goToPage(1);
              },
            ),
            _drawerItem(
              icon: Icons.notifications_active_rounded,
              title: 'Alerts',
              onTap: () {
                Navigator.pop(context);
                _goToPage(2);
              },
            ),
            _drawerItem(
              icon: Icons.person_rounded,
              title: 'Profile',
              onTap: () {
                Navigator.pop(context);
                _goToPage(3);
              },
            ),
            _drawerItem(
              icon: Icons.bluetooth_connected_rounded,
              title: 'Reconnect Device',
              onTap: () {
                Navigator.pop(context);
                _connectDevice();
              },
            ),
            const Spacer(),
            const Divider(height: 1),
            _drawerItem(
              icon: Icons.logout_rounded,
              title: 'Logout',
              iconColor: const Color(0xFFEF4444),
              textColor: const Color(0xFFEF4444),
              onTap: () {
                Navigator.pop(context);
                _showLogoutDialog();
              },
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color iconColor = const Color(0xFF3B82F6),
    Color textColor = const Color(0xFF0F172A),
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }

  Widget _homePage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _topBar(),
          const SizedBox(height: 18),
          _welcomeHeader(),
          const SizedBox(height: 16),
          _sectionHeader(),
          const SizedBox(height: 14),
          _connectionBanner(),
          const SizedBox(height: 14),
          _metricsGrid(),
          const SizedBox(height: 18),
          _reportCard(),
          const SizedBox(height: 18),
          _quickActionsCard(),
          const SizedBox(height: 18),
          _profilePreviewCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _historyPage() {
    final filteredHistory = _filteredHistoryData().reversed.toList();
    final averageHeartRate = _averageHeartRate();
    final averageSpo2 = _averageSpo2();
    final averageTemp = _averageTemperature();
    final hrPoints = _historyHrPoints();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _simpleTopBar('History'),
          const SizedBox(height: 18),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _historyFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return _filterChip(
                  _historyFilters[index],
                  selectedHistoryFilter == index,
                  onTap: () {
                    setState(() {
                      selectedHistoryFilter = index;
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _miniHistoryStat(
                  'Avg HR',
                  averageHeartRate == 0
                      ? '--'
                      : '${averageHeartRate.toStringAsFixed(0)} BPM',
                  const Color(0xFFEF4444),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniHistoryStat(
                  'Avg SpO₂',
                  averageSpo2 == 0
                      ? '--'
                      : '${averageSpo2.toStringAsFixed(0)}%',
                  const Color(0xFF3B82F6),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniHistoryStat(
                  'Avg Temp',
                  averageTemp == 0
                      ? '--'
                      : '${averageTemp.toStringAsFixed(1)}°C',
                  const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(15, 23, 42, 0.05),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Heart Rate Trend',
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hrPoints.isEmpty
                      ? 'No saved HR readings yet'
                      : 'Based on your recent saved logs',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 170,
                  child: hrPoints.isEmpty
                      ? const Center(
                          child: Text(
                            '--',
                            style: TextStyle(
                              fontSize: 26,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : CustomPaint(
                          size: const Size(double.infinity, 170),
                          painter: HistoryLineChartPainter(values: hrPoints),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Logs',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${filteredHistory.length} records',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF3B82F6),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (filteredHistory.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(15, 23, 42, 0.04),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: const Text(
                'No history data available yet. Connect the device and wait for readings to be saved.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ...filteredHistory.take(15).map((data) {
              final hrValue = (data['hr'] ?? 0) as num;
              final spo2Value = (data['spo2'] ?? 0) as num;
              final tempValue = (data['temp'] ?? 0) as num;

              final hr = hrValue <= 0 ? '--' : hrValue.toString();
              final savedSpo2 = spo2Value <= 0 ? '--' : spo2Value.toString();
              final savedTemp =
                  tempValue <= 0 ? '--' : tempValue.toStringAsFixed(1);

              final time = _formatHistoryTime(data['time']?.toString() ?? '');

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _logTile(
                  icon: Icons.monitor_heart_rounded,
                  iconBg: const Color(0xFFFFF1F2),
                  iconColor: const Color(0xFFEF4444),
                  title:
                      'HR: $hr BPM   |   SpO₂: $savedSpo2%   |   Temp: $savedTemp°C',
                  subtitle: time,
                  value: 'Saved',
                  status: 'Log',
                  statusColor: const Color(0xFF22C55E),
                ),
              );
            }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _miniHistoryStat(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 23, 42, 0.04),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertsPage() {
    final alerts = _buildAlerts();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _simpleTopBar('Emergency Center'),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isStable()
                  ? const Color(0xFFECFDF3)
                  : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isStable()
                    ? const Color(0xFF86EFAC)
                    : const Color(0xFFFCA5A5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isStable() ? Icons.check_circle_rounded : Icons.error_rounded,
                  color: isStable()
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFEF4444),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    alerts.first.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isStable()
                          ? const Color(0xFF166534)
                          : const Color(0xFFB91C1C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Emergency Contacts',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextButton(
                onPressed: showAddContactDialog,
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (emergencyContacts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(15, 23, 42, 0.04),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: const Text(
                'No emergency contacts added yet.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ...List.generate(emergencyContacts.length, (index) {
              final contact = emergencyContacts[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromRGBO(15, 23, 42, 0.04),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFFEFF6FF),
                        child: Icon(
                          Icons.person,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              contact['name'] ?? '',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              contact['phone'] ?? '',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => removeEmergencyContact(index),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),
          Center(
            child: GestureDetector(
              onTap: sendEmergencyAlert,
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFE4E6),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withOpacity(0.12),
                      blurRadius: 30,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF6B6B), Color(0xFFEF4444)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'SOS',
                          style: TextStyle(
                            fontSize: 30,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'TAP TO ALERT',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Live Alerts',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          ...alerts.map(
            (alert) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _notificationTile(
                icon: alert.icon,
                iconColor: alert.color,
                title: alert.title,
                subtitle: alert.subtitle,
              ),
            ),
          ),
          _notificationTile(
            icon: Icons.bluetooth_connected_rounded,
            iconColor: const Color(0xFF3B82F6),
            title: 'Device connection',
            subtitle: connectionStatus == 'Connected'
                ? 'OkHealth is connected and syncing live values.'
                : 'Connect device to enable live updates.',
          ),
          const SizedBox(height: 12),
          _notificationTile(
            icon: Icons.tune_rounded,
            iconColor: const Color(0xFFF59E0B),
            title: 'Warning thresholds',
            subtitle:
                'Heart Rate: 60-100 BPM, SpO₂: 95%+, Temp: 33.5-36.5 °C',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _profilePage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _simpleTopBar('Profile'),
          const SizedBox(height: 22),
          Center(
            child: Column(
              children: [
                Stack(
                  children: [
                    const CircleAvatar(
                      radius: 42,
                      backgroundColor: Color(0xFFE2E8F0),
                      child: Icon(
                        Icons.person,
                        size: 42,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  disease == 'None' ? 'Healthy profile' : disease,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _profileSummaryCard(),
          const SizedBox(height: 20),
          const Text(
            'Personal Health Information',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _profileField('Full Name', name),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _profileField('Age', age)),
              const SizedBox(width: 12),
              Expanded(child: _profileField('Gender', gender)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _profileField('Height', '$height cm')),
              const SizedBox(width: 12),
              Expanded(child: _profileField('Weight', '$weight kg')),
            ],
          ),
          const SizedBox(height: 12),
          _profileField('Medical Issue / Disease', disease),
          const SizedBox(height: 20),
          const Text(
            'Connected Device',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(15, 23, 42, 0.04),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.bluetooth_connected_rounded,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'OkHealth Sensor',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        connectionStatus,
                        style: TextStyle(
                          fontSize: 12,
                          color: connectionStatus == 'Connected'
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _connectDevice,
                  child: const Text('Reconnect'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: showEditProfileDialog,
              child: const Center(
                child: Text(
                  'Edit Profile',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _iconButton(
          icon: Icons.menu_rounded,
          onTap: _openDrawer,
        ),
        Row(
          children: [
            _iconButton(
              icon: isConnecting
                  ? Icons.bluetooth_searching_rounded
                  : Icons.bluetooth_connected_rounded,
              onTap: _connectDevice,
            ),
            const SizedBox(width: 10),
            _iconButton(
              icon: Icons.notifications_none_rounded,
              onTap: () => _goToPage(2),
            ),
            const SizedBox(width: 10),
            _iconButton(
              icon: Icons.logout_rounded,
              onTap: _showLogoutDialog,
            ),
          ],
        ),
      ],
    );
  }

  Widget _simpleTopBar(String title) {
    return Row(
      children: [
        _iconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: () => _goToPage(0),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _welcomeHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Good Morning,',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name.isEmpty ? 'Hritik Patel' : name,
                style: const TextStyle(
                  fontSize: 24,
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Live Health Data',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Row(
          children: [
            const Icon(
              Icons.bolt_rounded,
              size: 13,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(width: 4),
            Text(
              getUpdatedText(),
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _connectionBanner() {
    final connected = connectionStatus == 'Connected';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: connected
              ? [const Color(0xFFEFFCF4), const Color(0xFFF7FFFA)]
              : [const Color(0xFFEFF6FF), const Color(0xFFF8FBFF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: connected ? const Color(0xFFBBF7D0) : const Color(0xFFBFDBFE),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: connected
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              connected
                  ? Icons.bluetooth_connected_rounded
                  : Icons.bluetooth_searching_rounded,
              color:
                  connected ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'OkHealth connected' : connectionStatus,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  connected
                      ? 'Live health values are syncing from your device.'
                      : 'Tap the Bluetooth icon to scan and reconnect the sensor.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _metricCard(
                title: 'Heart Rate',
                value: heartRate == 0 ? '--' : heartRate.toString(),
                unit: 'BPM',
                subtitle: _isHeartRateNormal() ? 'Stable' : 'Check now',
                icon: Icons.favorite_rounded,
                iconBg: const Color(0xFFFFF1F2),
                iconColor: const Color(0xFFEF4444),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metricCard(
                title: 'Blood Oxygen',
                value: spo2 == 0 ? '--' : spo2.toString(),
                unit: '%',
                subtitle: _isSpo2Normal() ? 'SpO₂ normal' : 'Low oxygen',
                icon: Icons.water_drop_rounded,
                iconBg: const Color(0xFFEFF6FF),
                iconColor: const Color(0xFF3B82F6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                title: 'Temperature',
                value: temperature == 0.0
                    ? '--'
                    : temperature.toStringAsFixed(1),
                unit: '°C',
                subtitle: _isTemperatureNormal()
                    ? 'Temperature normal'
                    : 'Needs attention',
                icon: Icons.thermostat_rounded,
                iconBg: const Color(0xFFFFF7ED),
                iconColor: const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metricCard(
                title: 'Overall Status',
                value: getStatusText(),
                unit: '',
                subtitle: connectionStatus,
                icon: Icons.health_and_safety_rounded,
                iconBg: isStable()
                    ? const Color(0xFFECFDF3)
                    : const Color(0xFFFEF2F2),
                iconColor: getStatusColor(),
                statusMode: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String unit,
    required String subtitle,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    bool statusMode = false,
  }) {
    return Container(
      height: 145,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 23, 42, 0.05),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (!statusMode)
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      fontSize: 24,
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: unit.isEmpty || value == '--' ? '' : ' $unit',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                height: 1.1,
                color: getStatusColor(),
                fontWeight: FontWeight.w800,
              ),
            ),
          const Spacer(),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: statusMode ? getStatusColor() : const Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportCard() {
    final hrPoints = _historyHrPoints();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 23, 42, 0.05),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Daily Health Report',
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Today',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 140,
            child: hrPoints.isEmpty
                ? const Center(
                    child: Text(
                      '--',
                      style: TextStyle(
                        fontSize: 24,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : CustomPaint(
                    size: const Size(double.infinity, 140),
                    painter: HistoryLineChartPainter(values: hrPoints),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 23, 42, 0.05),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.bluetooth_connected_rounded,
                  title: 'Reconnect',
                  subtitle: 'Pair device',
                  onTap: _connectDevice,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  icon: Icons.notifications_active_rounded,
                  title: 'Alerts',
                  subtitle: 'View health warnings',
                  onTap: () => _goToPage(2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF3B82F6), size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profilePreviewCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8FBFF), Color(0xFFF3F7FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Personal Health Information',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _infoChip('Age', age),
              _infoChip('Gender', gender),
              _infoChip('Height', '$height cm'),
              _infoChip('Weight', '$weight kg'),
              _infoChip('Issue', disease),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 23, 42, 0.05),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _summaryStat('Heart', heartRate == 0 ? '--' : '$heartRate'),
          ),
          Expanded(
            child: _summaryStat('SpO₂', spo2 == 0 ? '--' : '$spo2%'),
          ),
          Expanded(
            child: _summaryStat(
              'Temp',
              temperature == 0.0 ? '--' : '${temperature.toStringAsFixed(1)}°C',
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF475569),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _filterChip(String text, bool selected, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF1FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color:
                selected ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _logTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String value,
    required String status,
    required Color statusColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 23, 42, 0.04),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                status,
                style: TextStyle(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _notificationTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 23, 42, 0.04),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _bottomNav() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 23, 42, 0.06),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(Icons.home_rounded, 'Home', 0),
          _navItem(Icons.bar_chart_rounded, 'History', 1),
          _navItem(Icons.notifications_none_rounded, 'Alerts', 2),
          _navItem(Icons.person_outline_rounded, 'Profile', 3),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final isSelected = selectedIndex == index;

    return GestureDetector(
      onTap: () => _goToPage(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color:
                isSelected ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8),
            size: 22,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isSelected
                  ? const Color(0xFF3B82F6)
                  : const Color(0xFF94A3B8),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 23, 42, 0.05),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(
          icon,
          color: const Color(0xFF64748B),
          size: 22,
        ),
      ),
    );
  }
}

class _HealthAlertItem {
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;

  const _HealthAlertItem({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
  });
}

class HistoryLineChartPainter extends CustomPainter {
  final List<double> values;

  HistoryLineChartPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    const leftPadding = 8.0;
    const rightPadding = 8.0;
    const topPadding = 10.0;
    const bottomPadding = 18.0;

    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;

    final gridPaint = Paint()
      ..color = const Color(0xFFEAEFF6)
      ..strokeWidth = 1;

    for (int i = 0; i < 4; i++) {
      final y = topPadding + (chartHeight / 3) * i;
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
    }

    double minValue = values.reduce(math.min);
    double maxValue = values.reduce(math.max);

    if ((maxValue - minValue).abs() < 1) {
      minValue -= 3;
      maxValue += 3;
    } else {
      minValue -= 5;
      maxValue += 5;
    }

    double mapY(double value) {
      final normalized = (value - minValue) / (maxValue - minValue);
      return topPadding + chartHeight - (normalized * chartHeight);
    }

    final points = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = leftPadding +
          (values.length == 1 ? chartWidth / 2 : (chartWidth / (values.length - 1)) * i);
      final y = mapY(values[i]);
      points.add(Offset(x, y));
    }

    final linePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF3B82F6).withOpacity(0.20),
          const Color(0xFF06B6D4).withOpacity(0.02),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();

    path.moveTo(points.first.dx, points.first.dy);
    fillPath.moveTo(points.first.dx, topPadding + chartHeight);
    fillPath.lineTo(points.first.dx, points.first.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final controlX = (p1.dx + p2.dx) / 2;

      path.cubicTo(controlX, p1.dy, controlX, p2.dy, p2.dx, p2.dy);
      fillPath.cubicTo(controlX, p1.dy, controlX, p2.dy, p2.dx, p2.dy);
    }

    fillPath.lineTo(points.last.dx, topPadding + chartHeight);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = const Color(0xFF3B82F6);
    final ringPaint = Paint()
      ..color = const Color(0xFF3B82F6).withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;

    final lastPoint = points.last;
    canvas.drawCircle(lastPoint, 5, dotPaint);
    canvas.drawCircle(lastPoint, 12, ringPaint);
  }

  @override
  bool shouldRepaint(covariant HistoryLineChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}
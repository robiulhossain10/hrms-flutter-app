import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import 'widgets/attendance_widgets.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final Dio dio = Dio();

  bool loading = false;
  bool isInitialLoading = true;
  bool isCheckedIn = false;
  bool serverOnline = false;

  String logText = "";
  Map<String, dynamic>? serverInfo;
  Map<String, dynamic>? summary;
  List attendanceList = [];

  DateTime currentMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    try {
      await Future.wait([
        loadServerStatus(),
        loadSummary(),
        loadCalendarData(),
      ]);
      _checkTodayStatus();
    } finally {
      if (mounted) {
        setState(() => isInitialLoading = false);
      }
    }
  }

  void _checkTodayStatus() {
    String today = DateTime.now().toIso8601String().split("T")[0];
    var todayRecord = attendanceList.cast<Map<String, dynamic>?>().firstWhere(
          (r) => r?['date'] == today,
      orElse: () => null,
    );
    if (todayRecord != null && todayRecord['checkOutTime'] == null) {
      setState(() {
        isCheckedIn = true;
      });
    }
  }

  void addLog(String text) {
    debugPrint(text);
    setState(() {
      logText =
      "[${DateTime.now().toIso8601String().split('T')[1].substring(0, 8)}] $text\n\n$logText";
    });
  }

  void _showSnackBar(String message, bool isSuccess) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
              color: isSuccess
                  ? const Color(0xFF00E5A0)
                  : const Color(0xFFFF5C72),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFFF0F2F8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF151A30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }

  Future<Position> getGps() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception("Location service disabled");
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception("Location permission denied");
    }
    return Geolocator.getCurrentPosition(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
      ),
    );
  }

  Future<void> loadServerStatus() async {
    try {
      final res = await dio.get("${AppConstants.baseUrl}/");
      setState(() {
        serverInfo = res.data;
        serverOnline = true;
      });
      addLog("SERVER CONNECTED: ${serverInfo?['office']?['officeName']}");
    } catch (e) {
      setState(() => serverOnline = false);
      addLog("SERVER OFFLINE");
    }
  }

  Future<void> checkIn() async {
    try {
      setState(() => loading = true);
      addLog("CHECK-IN STARTED");
      Position position = await getGps();

      final res = await dio.post(
        "${AppConstants.baseUrl}/api/attendance/checkin",
        data: {
          "latitude": position.latitude,
          "longitude": position.longitude,
          "accuracy": position.accuracy,
          "deviceTime": DateTime.now().toIso8601String(),
          "deviceId": AppConstants.deviceId,
        },
        options: Options(headers: {"Authorization": "Bearer ${AppConstants.authToken}"}),
      );

      if (res.data['status'] == 'SUCCESS') {
        addLog(
          "CHECK-IN SUCCESS (Distance: ${res.data['attendance']['distance']}m)",
        );
        _showSnackBar("Checked In Successfully", true);
        setState(() => isCheckedIn = true);
        await loadSummary();
        await loadCalendarData();
      }
    } on DioException catch (e) {
      String msg = e.response?.data?['message'] ?? "Check-in failed";
      addLog("CHECK-IN FAILED: $msg");
      _showSnackBar(msg, false);
    } catch (e) {
      addLog("CHECK-IN ERROR: $e");
      _showSnackBar("An unexpected error occurred", false);
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> checkOut() async {
    try {
      setState(() => loading = true);
      addLog("CHECK-OUT STARTED");
      Position position = await getGps();

      final res = await dio.post(
        "${AppConstants.baseUrl}/api/attendance/checkout",
        data: {
          "latitude": position.latitude,
          "longitude": position.longitude,
          "accuracy": position.accuracy,
          "deviceTime": DateTime.now().toIso8601String(),
          "deviceId": AppConstants.deviceId,
        },
        options: Options(headers: {"Authorization": "Bearer ${AppConstants.authToken}"}),
      );

      if (res.data['status'] == 'SUCCESS') {
        addLog("CHECK-OUT SUCCESS");
        _showSnackBar("Checked Out Successfully", true);
        setState(() => isCheckedIn = false);
        await loadSummary();
        await loadCalendarData();
      }
    } on DioException catch (e) {
      String msg = e.response?.data?['message'] ?? "Check-out failed";
      addLog("CHECK-OUT FAILED: $msg");
      _showSnackBar(msg, false);
    } catch (e) {
      addLog("CHECK-OUT ERROR: $e");
      _showSnackBar("An unexpected error occurred", false);
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> loadSummary() async {
    try {
      final res = await dio.get("${AppConstants.baseUrl}/api/attendance/summary/${AppConstants.userId}");
      setState(() => summary = res.data);
    } catch (e) {
      addLog("SUMMARY LOAD ERROR");
    }
  }

  Future<void> loadCalendarData() async {
    try {
      String year = currentMonth.year.toString();
      String month = currentMonth.month.toString().padLeft(2, '0');
      final res = await dio.get(
        "${AppConstants.baseUrl}/api/attendance/calendar/${AppConstants.userId}/$year/$month",
      );
      setState(() => attendanceList = res.data['records'] ?? []);
    } catch (e) {
      addLog("CALENDAR LOAD ERROR");
    }
  }

  Future<void> refreshData() async {
    await loadServerStatus();
    await loadSummary();
    await loadCalendarData();
    _checkTodayStatus();
  }

  void _prevMonth() {
    setState(
          () => currentMonth = DateTime(currentMonth.year, currentMonth.month - 1),
    );
    loadCalendarData();
  }

  void _nextMonth() {
    setState(
          () => currentMonth = DateTime(currentMonth.year, currentMonth.month + 1),
    );
    loadCalendarData();
  }

  @override
  Widget build(BuildContext context) {
    if (isInitialLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF06080F),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF7C5CFC),
          ),
        ),
      );
    }
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            flexibleSpace: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(32),
              ),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF7C5CFC),
                      Color(0xFF5238C7),
                      Color(0xFF00E5A0),
                    ],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
                child: FlexibleSpaceBar(
                  title: const Text(
                    "Attendance",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      letterSpacing: 0.5,
                    ),
                  ),
                  titlePadding: const EdgeInsets.only(left: 24, bottom: 20),
                  background: Stack(
                    children: [
                      Positioned(
                        right: -40,
                        top: -40,
                        child: Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 50,
                        top: 60,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      Positioned(
                        left: -30,
                        bottom: 20,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.04),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 60,
                        bottom: 80,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: RefreshIndicator(
              onRefresh: refreshData,
              color: const Color(0xFF7C5CFC),
              backgroundColor: const Color(0xFF151A30),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildServerStatusChip(),
                    const SizedBox(height: 24),
                    _buildSummaryCard(),
                    const SizedBox(height: 28),
                    _buildToggleButton(),
                    const SizedBox(height: 36),
                    _buildSectionTitle("Attendance Records", Icons.history),
                    const SizedBox(height: 16),
                    _buildMonthSelector(),
                    const SizedBox(height: 14),
                    if (attendanceList.isEmpty)
                      _buildEmptyState()
                    else
                      ...attendanceList.map(
                            (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _buildRecordCard(item),
                        ),
                      ),
                    const SizedBox(height: 36),
                    _buildSectionTitle("System Logs", Icons.terminal),
                    const SizedBox(height: 14),
                    _buildLogPanel(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI WIDGETS ---

  Widget _buildServerStatusChip() {
    final accentColor = serverOnline
        ? const Color(0xFF00E5A0)
        : const Color(0xFFFF5C72);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: accentColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor,
              boxShadow: [
                BoxShadow(color: accentColor.withValues(alpha: 0.6), blurRadius: 8),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            serverOnline
                ? "Connected to ${serverInfo?['office']?['officeName'] ?? 'Office'}"
                : "Server Offline",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accentColor.withValues(alpha: 0.9),
            ),
          ),
          const Spacer(),
          if (serverOnline)
            Text(
              "Radius: ${serverInfo?['office']?['radiusMeter']}m",
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E1225), Color(0xFF141A35)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C5CFC).withValues(alpha: 0.06),
            blurRadius: 40,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF7C5CFC).withValues(alpha: 0.2),
                      const Color(0xFF7C5CFC).withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.dashboard_rounded,
                  color: Color(0xFF7C5CFC),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  "Attendance Summary",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF0F2F8),
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: StatBlock(
                  value: "${summary?['totalPresent'] ?? 0}",
                  label: "Present Days",
                  icon: Icons.calendar_today_rounded,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E5A0), Color(0xFF00B880)],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatBlock(
                  value: "${summary?['totalWorkingHours'] ?? 0} hrs",
                  label: "Working Hours",
                  icon: Icons.access_time_rounded,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFB347), Color(0xFFFF8C42)],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton() {
    final isCheckOut = isCheckedIn;
    final activeGradient = isCheckOut
        ? const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFF5C72), Color(0xFFE0324A)],
    )
        : const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF00E5A0), Color(0xFF00C98D)],
    );
    final activeShadowColor = isCheckOut
        ? const Color(0xFFFF5C72)
        : const Color(0xFF00E5A0);

    return Container(
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: loading ? null : activeGradient,
        color: loading ? const Color(0xFF151A30) : null,
        border: Border.all(
          color: loading
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.12),
        ),
        boxShadow: loading
            ? []
            : [
          BoxShadow(
            color: activeShadowColor.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : (isCheckOut ? checkOut : checkIn),
          borderRadius: BorderRadius.circular(24),
          child: Center(
            child: loading
                ? const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
                : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isCheckOut
                      ? Icons.power_settings_new_rounded
                      : Icons.fingerprint_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Text(
                  isCheckOut ? "CHECK OUT" : "CHECK IN",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1225),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(
              Icons.chevron_left,
              color: Color(0xFF7C5CFC),
              size: 28,
            ),
            onPressed: _prevMonth,
          ),
          Text(
            DateFormat.yMMMM().format(currentMonth),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF0F2F8),
              letterSpacing: 0.5,
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.chevron_right,
              color: Color(0xFF7C5CFC),
              size: 28,
            ),
            onPressed: _nextMonth,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF7C5CFC).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF7C5CFC), size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF0F2F8),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF7C5CFC).withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1225),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inbox_rounded,
              size: 48,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "No records for this month",
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.3),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> item) {
    final hasCheckout =
        item['checkOutTime'] != null &&
            item['checkOutTime'].toString().isNotEmpty &&
            item['checkOutTime'].toString() != 'null';
    final minutes = item['workingMinutes'] ?? 0;

    String formatTime(String? isoTime) {
      if (isoTime == null || isoTime.isEmpty || isoTime == 'null') {
        return "--:--";
      }
      try {
        return isoTime.split('T')[1].substring(0, 5);
      } catch (e) {
        return "--:--";
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1225),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C5CFC).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.event_note_rounded,
                    color: Color(0xFF7C5CFC),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item["date"].toString(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF0F2F8),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: hasCheckout
                        ? const Color(0xFF00E5A0).withValues(alpha: 0.1)
                        : const Color(0xFFFFB347).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    hasCheckout ? "Completed" : "In Progress",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: hasCheckout
                          ? const Color(0xFF00E5A0)
                          : const Color(0xFFFFB347),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.03)),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildTimeChip(
                  icon: Icons.play_arrow_rounded,
                  label: "In",
                  time: formatTime(item['checkInTime']?.toString()),
                  color: const Color(0xFF00E5A0),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    width: 24,
                    height: 1.5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                _buildTimeChip(
                  icon: Icons.stop_rounded,
                  label: "Out",
                  time: formatTime(item['checkOutTime']?.toString()),
                  color: const Color(0xFFFF5C72),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB347).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: const Color(0xFFFFB347).withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        hasCheckout ? "$minutes m" : "--",
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFFB347),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (item['distance'] != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.gps_fixed,
                      size: 12,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Dist: ${item['distance']}m  •  Acc: ${item['accuracy'] ?? 'N/A'}m",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.3),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimeChip({
    required IconData icon,
    required String label,
    required String time,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.5),
                letterSpacing: 0.8,
              ),
            ),
            Text(
              time,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color.withValues(alpha: 0.95),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLogPanel() {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: const Color(0xFF06080F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF7C5CFC).withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C5CFC).withValues(alpha: 0.03),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF7C5CFC).withValues(alpha: 0.04),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFF7C5CFC).withValues(alpha: 0.08),
                ),
              ),
            ),
            child: Row(
              children: [
                TerminalDot(color: const Color(0xFFFF5C72)),
                const SizedBox(width: 8),
                TerminalDot(color: const Color(0xFFFFB347)),
                const SizedBox(width: 8),
                TerminalDot(color: const Color(0xFF00E5A0)),
                const SizedBox(width: 16),
                Text(
                  "terminal",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.2),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: SelectableText(
                logText.isEmpty ? "// Waiting for activity..." : logText,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.7,
                  color: logText.isEmpty
                      ? Colors.white.withValues(alpha: 0.1)
                      : const Color(0xFF00E5A0).withValues(alpha: 0.7),
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

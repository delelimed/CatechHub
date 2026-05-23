import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/storage/local_database.dart';
import '../features/auth/login_page.dart';
import '../features/classes/my_group_page.dart';
import '../features/classes/group_management_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/students/students_page.dart';
import '../shared/models/student_model.dart';
import '../features/students/student_detail_page.dart';
import '../features/meetings/attendance_meetings_page.dart';
import '../features/meetings/attendance_page.dart';
import '../features/planning/planning_page.dart';
import '../features/documents/documents_page.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/privacy.dart';
import '../features/documents/document_detail_page.dart';
import '../features/sussidio/sussidio.dart';

final appRouter = GoRouter(
  initialLocation: '/',

  redirect: (context, state) {
    // 📦 Accediamo al box crittografato aperto nel main
    final box = LocalDatabase.auth();
    
    // Controlliamo se esiste una sessione attiva o un flag di sblocco locale
    // Puoi impostare questo valore su 'true' quando la password locale è corretta
    final bool isLoggedLocally = box.get('isLoggedIn', defaultValue: false);
    final isLoginPath = state.matchedLocation == '/login';

    // 🔐 Logica di reindirizzamento offline
    if (!isLoggedLocally && !isLoginPath) return '/login';
    if (isLoggedLocally && isLoginPath) return '/';

    return null;
  },

  routes: [
    /// AUTH (Schermata di sblocco locale)
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),

    /// DASHBOARD
    GoRoute(
      path: '/',
      builder: (context, state) => const DashboardPage(),
    ),

    /// STUDENTS
    GoRoute(
      path: '/students',
      builder: (context, state) => const StudentsPage(),
    ),

    GoRoute(
      path: '/student-detail',
      builder: (context, state) => const StudentDetailPage(),
    ),

    /// ATTENDANCE FLOW
    GoRoute(
      path: '/attendance-meetings',
      builder: (context, state) => const AttendanceMeetingsPage(),
    ),

    GoRoute(
      path: '/attendance',
      builder: (context, state) {
        final meeting = state.extra;
        return AttendancePage(meeting: meeting);
      },
    ),

    /// PLANNING
    GoRoute(
      path: '/planning',
      builder: (context, state) => const PlanningPage(),
    ),

    /// DOCUMENTS
    GoRoute(
      path: '/documents',
      builder: (context, state) => const DocumentsPage(),
    ),

    GoRoute(
      path: '/document-detail',
      builder: (context, state) {
        final extraData = state.extra as Map<String, dynamic>? ?? {};
        
        return DocumentDetailPage(
          document: extraData['document'] as Map<String, dynamic>? ?? {},
          students: extraData['students'] as List<Student>? ?? [],
        );
      },
    ),

    /// SETTINGS
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),

    GoRoute(
      path: '/privacy-security',
      builder: (context, state) => const PrivacySecurityPage(),
    ),

    /// MY GROUP
    GoRoute(
      path: '/my-group',
      builder: (context, state) => const MyGroupPage(),
    ),

    /// GROUP MANAGEMENT
    GoRoute(
      path: '/group-management',
      builder: (context, state) => const GroupManagementPage(),
    ),

    /// SUSSIDIO
    GoRoute(
      path: '/sussidio',
      builder: (context, state) => const SussidioPage(),
    ),
  ],
);
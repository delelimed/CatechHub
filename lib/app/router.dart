import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/storage/local_database.dart';
import '../features/classes/my_group_page.dart';
import '../features/classes/group_management_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/classes/classes_page.dart';
import '../features/classes/class_detail_page.dart';
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
import '../features/auth/login_page.dart';

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
      builder: (_, __) => const LoginPage(),
    ),

    /// DASHBOARD
    GoRoute(
      path: '/',
      builder: (_, __) => const DashboardPage(),
    ),

    /// CLASSES
    GoRoute(
      path: '/classes',
      builder: (_, __) => const ClassesPage(),
    ),

    GoRoute(
      path: '/class-detail',
      builder: (_, state) {
        final classId = state.extra as String;
        return ClassDetailPage(classId: classId);
      },
    ),

    /// STUDENTS
    GoRoute(
      path: '/students',
      builder: (_, __) => const StudentsPage(),
    ),

    GoRoute(
      path: '/student-detail',
      builder: (_, __) => const StudentDetailPage(),
    ),

    /// ATTENDANCE FLOW
    GoRoute(
      path: '/attendance-meetings',
      builder: (_, __) => const AttendanceMeetingsPage(),
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
      builder: (_, __) => const PlanningPage(),
    ),

    /// DOCUMENTS
    GoRoute(
      path: '/documents',
      builder: (_, __) => const DocumentsPage(),
    ),

    GoRoute(
      path: '/document-detail',
      builder: (_, state) {
        final extraData = state.extra as Map<String, dynamic>;
        
        return DocumentDetailPage(
          document: extraData['document'] as Map<String, dynamic>,
          students: extraData['students'] as List<Student>,
        );
      },
    ),

    /// SETTINGS
    GoRoute(
      path: '/settings',
      builder: (_, __) => const SettingsPage(),
    ),

    GoRoute(
      path: '/privacy-security',
      builder: (_, __) => const PrivacySecurityPage(),
    ),

    /// MY GROUP
    GoRoute(
      path: '/my-group',
      builder: (_, __) => const MyGroupPage(),
    ),

    /// GROUP MANAGEMENT
    GoRoute(
      path: '/group-management',
      builder: (_, __) => const GroupManagementPage(),
    ),
  ],
);

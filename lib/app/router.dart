import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_provider.dart';
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
import '../features/settings/delete_data_page.dart';
import '../features/settings/change_pin_page.dart';
import '../features/documents/document_detail_page.dart';
import '../features/students/allergies_page.dart';
import '../features/students/autonomous_exits_page.dart';
import '../features/phone_verification/verify_number_page.dart';
import '../features/update/update_page.dart';
import '../features/data_share/data_share_selection_page.dart';
import '../features/data_share/data_share_send_page.dart';
import '../features/data_share/data_share_receive_page.dart';

class _AuthStateNotifier extends ChangeNotifier {
  _AuthStateNotifier(Ref ref) {
    ref.listen(authStateProvider, (prev, next) {
      notifyListeners();
    });
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthStateNotifier(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoginPath = state.matchedLocation == '/login';

      return authState.when(
        loading: () => null,
        error: (_, __) => isLoginPath ? null : '/login',
        data: (user) {
          if (user == null && !isLoginPath) return '/login';
          if (user != null && isLoginPath) return '/';
          return null;
        },
      );
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

    GoRoute(
      path: '/delete-data',
      builder: (context, state) => const DeleteDataPage(),
    ),

    GoRoute(
      path: '/change-pin',
      builder: (context, state) => const ChangePinPage(),
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

    /// ALLERGIES
    GoRoute(
      path: '/allergies',
      builder: (context, state) => const AllergiesPage(),
    ),

    /// AUTONOMOUS EXITS
    GoRoute(
      path: '/autonomous-exits',
      builder: (context, state) => const AutonomousExitsPage(),
    ),

    /// VERIFY NUMBER
    GoRoute(
      path: '/verify-number',
      builder: (context, state) => const VerifyNumberPage(),
    ),

    /// UPDATES
    GoRoute(
      path: '/updates',
      builder: (context, state) => const UpdatePage(),
    ),

    /// DATA SHARE
    GoRoute(
      path: '/data-share',
      builder: (context, state) => const DataShareSelectionPage(),
    ),

    GoRoute(
      path: '/data-share/send',
      builder: (context, state) => const DataShareSendPage(),
    ),

    GoRoute(
      path: '/data-share/receive',
      builder: (context, state) => const DataShareReceivePage(),
    ),
  ],
  );
});

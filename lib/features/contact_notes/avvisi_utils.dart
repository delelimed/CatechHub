import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/student_model.dart';
import '../meetings/attendance_repository.dart';

bool hasPlaceholders(String text) {
  return text.contains('{');
}

String resolvePlaceholders(
  String text,
  Student student, {
  String? parentName,
  String? groupName,
  String? meetingDate,
  int? consecutiveAbsences,
  String? lastPresenceDate,
}) {
  String result = text;

  result = result.replaceAll('{nome_ragazzo}', student.name);
  result = result.replaceAll('{cognome_ragazzo}', student.surname);

  if (parentName != null) {
    result = result.replaceAll('{nome_genitore}', parentName);
  }
  if (groupName != null) {
    result = result.replaceAll('{nome_gruppo}', groupName);
  }
  if (meetingDate != null) {
    result = result.replaceAll('{data_incontro}', meetingDate);
  }
  if (consecutiveAbsences != null) {
    result = result.replaceAll('{assenze_consecutive}', consecutiveAbsences.toString());
  }
  if (lastPresenceDate != null) {
    result = result.replaceAll('{ultima_presenza}', lastPresenceDate);
  }

  return result;
}

class AbsenceData {
  final int consecutiveAbsences;
  final String? lastPresenceDate;

  AbsenceData({
    required this.consecutiveAbsences,
    this.lastPresenceDate,
  });
}

AbsenceData computeAbsenceData(String studentId, String classId) {
  final repo = AttendanceRepository();
  final attendances = repo.getAttendanceSync();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final classMeetings = attendances
      .where((a) => a['classId'] == classId)
      .where((a) {
        final meetingDate = DateTime.tryParse(a['date']?.toString() ?? '');
        if (meetingDate == null) return false;
        final meetingDay = DateTime(meetingDate.year, meetingDate.month, meetingDate.day);
        return !meetingDay.isAfter(today);
      })
      .toList()
    ..sort((a, b) {
      final aDate = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime.now();
      final bDate = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

  int consecutive = 0;
  String? lastPresence;

  for (final meeting in classMeetings) {
    final presence = meeting['presence'] as Map<String, dynamic>? ?? {};
    final status = presence[studentId]?.toString() ?? '';

    if (status == 'Presente') {
      if (lastPresence == null) {
        final meetingDate = DateTime.tryParse(meeting['date']?.toString() ?? '');
        if (meetingDate != null) {
          lastPresence =
              '${meetingDate.day.toString().padLeft(2, '0')}/${meetingDate.month.toString().padLeft(2, '0')}/${meetingDate.year}';
        }
      }
      break;
    } else if (status == 'Assente' || status == 'Giustificato') {
      consecutive++;
    }
  }

  return AbsenceData(
    consecutiveAbsences: consecutive,
    lastPresenceDate: lastPresence,
  );
}

void openWhatsApp(String? phone, String message) async {
  final encoded = Uri.encodeQueryComponent(message);
  String url;
  if (phone != null && phone.isNotEmpty) {
    final normalized = phone.replaceAll(RegExp(r'[^0-9]'), '');
    url = 'https://wa.me/$normalized?text=$encoded';
  } else {
    url = 'https://api.whatsapp.com/send?text=$encoded';
  }
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

import 'package:intl/intl.dart';
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
  if (studentId.isEmpty) {
    return AbsenceData(consecutiveAbsences: 0);
  }

  final repo = AttendanceRepository();
  final attendances = repo.getAttendanceSync();

  try {
    final sortedRecords = attendances.toList()
      ..sort((a, b) {
        final aDate = DateTime.tryParse(a['date']?.toString() ?? '') ??
            DateTime.now();
        final bDate = DateTime.tryParse(b['date']?.toString() ?? '') ??
            DateTime.now();
        return bDate.compareTo(aDate);
      });

    int consecutiveAbsences = 0;
    String? lastPresenceDate;
    bool countingConsecutive = true;

    for (final record in sortedRecords) {
      final presenceMap =
          Map<String, dynamic>.from(record['presence'] as Map? ?? {});
      final studentStatus = presenceMap[studentId]?.toString();

      if (studentStatus == null) continue;

      if (studentStatus == 'Assente') {
        if (countingConsecutive) {
          consecutiveAbsences++;
        }
      } else if (studentStatus == 'Giustificato') {
        if (countingConsecutive) {
          consecutiveAbsences++;
        }
      } else if (studentStatus == 'Presente') {
        if (lastPresenceDate == null) {
          final date = DateTime.tryParse(record['date']?.toString() ?? '');
          if (date != null) {
            lastPresenceDate = DateFormat('dd/MM/yyyy').format(date);
          }
        }
        countingConsecutive = false;
      }
    }

    return AbsenceData(
      consecutiveAbsences: consecutiveAbsences,
      lastPresenceDate: lastPresenceDate,
    );
  } catch (e) {
    return AbsenceData(consecutiveAbsences: 0);
  }
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

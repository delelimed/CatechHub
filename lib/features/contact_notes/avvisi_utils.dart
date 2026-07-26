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
  if (classId.isEmpty || studentId.isEmpty) {
    return AbsenceData(consecutiveAbsences: 0);
  }

  final repo = AttendanceRepository();
  final attendances = repo.getAttendanceSync();

  try {
    final classMeetings = <Map<String, dynamic>>[];
    for (final a in attendances) {
      final aClassId = a['classId']?.toString();
      if (aClassId == null || aClassId != classId) continue;
      final dateStr = a['date']?.toString();
      if (dateStr == null || dateStr.isEmpty) continue;
      classMeetings.add(a);
    }
    classMeetings.sort((a, b) {
      final aDate = DateTime.tryParse(a['date']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse(b['date']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    int consecutive = 0;
    String? lastPresence;

    for (final meeting in classMeetings) {
      final presenceRaw = meeting['presence'];
      if (presenceRaw == null) continue;
      final presence = (presenceRaw is Map)
          ? Map<String, dynamic>.from(presenceRaw)
          : <String, dynamic>{};
      final status = presence[studentId]?.toString() ?? '';

      if (status == 'Presente') {
        if (lastPresence == null) {
          final meetingDate =
              DateTime.tryParse(meeting['date']?.toString() ?? '');
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

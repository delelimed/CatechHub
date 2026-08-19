// ══════════════════════════════════════════════════════════════════════════════
// catechist_profile.dart — CatechHub (rubrica catechisti della parrocchia)
//
// Modulo "Responsabile Catechistico": rappresenta un catechista della
// parrocchia come entità anagrafica (nome, cognome, telefono) con un
// [catechistId] stabile. È il punto di riferimento per:
//   - assegnare il catechista a una o più classi (catechistIds nelle classi);
//   - collegare il catechista ai dispositivi associati via P2P (stesso
//     catechistId in [P2PDeviceAssociation]).
//
// Il record è persistito nel box Hive `catechists_box` con chiave = id.
// La scrittura è riservata al ruolo Responsabile.
// ══════════════════════════════════════════════════════════════════════════════

/// Profilo anagrafico di un catechista della parrocchia.
class CatechistProfile {
  /// ID stabile del catechista (coincide con il catechistId usato nelle
  /// classi e nelle associazioni P2P).
  final String id;

  /// Nome del catechista.
  final String firstName;

  /// Cognome del catechista.
  final String lastName;

  /// Numero di telefono del catechista.
  final String phone;

  /// Timestamp di creazione del profilo.
  final DateTime createdAt;

  CatechistProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.phone = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Nome completo del catechista (es. "Maria Rossi").
  String get fullName => '$firstName $lastName'.trim();

  /// Iniziali (es. "MR") per gli avatar.
  String get initials {
    final a = firstName.trim().isNotEmpty ? firstName.trim()[0] : '';
    final b = lastName.trim().isNotEmpty ? lastName.trim()[0] : '';
    return '$a$b'.toUpperCase();
  }

  CatechistProfile copyWith({
    String? firstName,
    String? lastName,
    String? phone,
  }) {
    return CatechistProfile(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      createdAt: createdAt,
    );
  }

  factory CatechistProfile.fromMap(String id, Map<String, dynamic> data) {
    return CatechistProfile(
      id: id,
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      phone: data['phone'] ?? '',
      createdAt:
          DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'phone': phone,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

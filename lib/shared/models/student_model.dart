class Student {
  final String id;
  final String name;
  final String surname;
  final String? classId;
  final DateTime birthDate;

  final String motherName;
  final String motherSurname;

  final String fatherName;
  final String fatherSurname;

  final String motherPhone;
  final String fatherPhone;
  final String studentPhone;

  final String? allergies;
  final String? autonomousExits;
  final String? notes;

  Student({
    required this.id,
    required this.name,
    required this.surname,
    required this.birthDate,
    required this.motherName,
    required this.motherSurname,
    required this.fatherName,
    required this.fatherSurname,
    required this.motherPhone,
    required this.fatherPhone,
    required this.studentPhone,
    this.classId,
    this.allergies,
    this.autonomousExits,
    this.notes,
  });

  factory Student.fromMap(String id, Map<String, dynamic> data) {
    return Student(
      id: id,
      name: data['name'] ?? '',
      surname: data['surname'] ?? '',
      birthDate: DateTime.tryParse(data['birthDate']?.toString() ?? '') ??
          DateTime.now(),
      classId: data['classId'],

      motherName: data['motherName'] ?? '',
      motherSurname: data['motherSurname'] ?? '',

      fatherName: data['fatherName'] ?? '',
      fatherSurname: data['fatherSurname'] ?? '',

      motherPhone: data['motherPhone'] ?? '',
      fatherPhone: data['fatherPhone'] ?? '',
      studentPhone: data['studentPhone'] ?? '',

      allergies: data['allergies'],
      autonomousExits: data['autonomousExits'],
      notes: data['notes'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'surname': surname,
      'birthDate': birthDate.toIso8601String(),
      'classId': classId,

      'motherName': motherName,
      'motherSurname': motherSurname,

      'fatherName': fatherName,
      'fatherSurname': fatherSurname,

      'motherPhone': motherPhone,
      'fatherPhone': fatherPhone,
      'studentPhone': studentPhone,

      'allergies': allergies,
      'autonomousExits': autonomousExits,
      'notes': notes,
    };
  }
}

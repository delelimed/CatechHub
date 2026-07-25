class AvvisoTemplate {
  final String id;
  final String title;
  final String text;

  static const placeholders = <_Placeholder>[
    _Placeholder('{nome_ragazzo}', 'Nome del ragazzo'),
    _Placeholder('{cognome_ragazzo}', 'Cognome del ragazzo'),
    _Placeholder('{nome_genitore}', 'Nome del genitore'),
    _Placeholder('{nome_gruppo}', 'Nome del gruppo'),
    _Placeholder('{data_incontro}', 'Data del prossimo incontro'),
    _Placeholder('{ora_incontro}', 'Ora del prossimo incontro'),
  ];

  const AvvisoTemplate({
    required this.id,
    required this.title,
    required this.text,
  });

  factory AvvisoTemplate.fromMap(String id, Map<String, dynamic> data) {
    return AvvisoTemplate(
      id: id,
      title: data['title'] ?? '',
      text: data['text'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'text': text,
    };
  }

  AvvisoTemplate copyWith({
    String? id,
    String? title,
    String? text,
  }) {
    return AvvisoTemplate(
      id: id ?? this.id,
      title: title ?? this.title,
      text: text ?? this.text,
    );
  }
}

class _Placeholder {
  final String code;
  final String description;
  const _Placeholder(this.code, this.description);
}

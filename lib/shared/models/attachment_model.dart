class Attachment {
  final String id;
  final String parentId;
  final String parentType;
  final String name;
  final String mimeType;
  final int size;
  final DateTime createdAt;
  final String fileHash;
  final String? description;

  Attachment({
    required this.id,
    required this.parentId,
    required this.parentType,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.createdAt,
    required this.fileHash,
    this.description,
  });

  factory Attachment.fromMap(String id, Map<String, dynamic> data) {
    return Attachment(
      id: id,
      parentId: data['parentId'] ?? '',
      parentType: data['parentType'] ?? '',
      name: data['name'] ?? '',
      mimeType: data['mimeType'] ?? 'application/octet-stream',
      size: data['size'] ?? 0,
      createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      fileHash: data['fileHash'] ?? '',
      description: data['description'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'parentId': parentId,
      'parentType': parentType,
      'name': name,
      'mimeType': mimeType,
      'size': size,
      'createdAt': createdAt.toIso8601String(),
      'fileHash': fileHash,
      'description': description,
    };
  }

  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool get isImage => mimeType.startsWith('image/');
  bool get isPdf => mimeType == 'application/pdf';
}

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as image;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers/class_scoped_providers.dart';
import '../../core/providers/current_class_provider.dart';
import '../../shared/models/student_model.dart';
import '../../shared/models/student_relation_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'student_relations_repository.dart';

final _studentRelationsByClassProvider = StreamProvider.autoDispose
    .family<List<StudentRelation>, String>((ref, classCode) {
      return ref
          .read(studentRelationsRepositoryProvider)
          .watchByClass(classCode);
    });

class StudentRelationsPage extends ConsumerStatefulWidget {
  final String? focusStudentId;

  const StudentRelationsPage({super.key, this.focusStudentId});

  @override
  ConsumerState<StudentRelationsPage> createState() =>
      _StudentRelationsPageState();
}

class _StudentRelationsPageState extends ConsumerState<StudentRelationsPage> {
  final _graphKey = GlobalKey();

  Future<void> _exportGraph({
    required String className,
    required bool jpeg,
  }) async {
    final boundary =
        _graphKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final pngBytes = await boundary.toImage(pixelRatio: 3).then((image) async {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final bytes = jpeg
        ? Uint8List.fromList(
            image.encodeJpg(image.decodePng(pngBytes)!, quality: 92),
          )
        : pngBytes;
    final directory = await getTemporaryDirectory();
    final extension = jpeg ? 'jpg' : 'png';
    final file = File(
      '${directory.path}/grafico_rapporti_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'GRAFICO RAPPORTI $className',
      ),
    );
  }

  Future<void> _editRelation(
    BuildContext context,
    List<Student> students,
    StudentRelation? existing,
    String classCode,
  ) async {
    var firstId = existing?.studentAId ?? widget.focusStudentId;
    var secondId = existing?.studentBId;
    var type = existing?.type ?? StudentRelationType.friendship;
    final repository = ref.read(studentRelationsRepositoryProvider);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'Nuovo rapporto' : 'Modifica rapporto',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: firstId,
                decoration: const InputDecoration(labelText: 'Ragazzo'),
                items: students
                    .map(
                      (student) => DropdownMenuItem(
                        value: student.id,
                        child: Text('${student.surname} ${student.name}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => firstId = value),
              ),
              DropdownButtonFormField<String>(
                initialValue: secondId,
                decoration: const InputDecoration(labelText: 'Altro ragazzo'),
                items: students
                    .map(
                      (student) => DropdownMenuItem(
                        value: student.id,
                        child: Text('${student.surname} ${student.name}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => secondId = value),
              ),
              const SizedBox(height: 12),
              SegmentedButton<StudentRelationType>(
                segments: const [
                  ButtonSegment(
                    value: StudentRelationType.friendship,
                    label: Text('Amicizia'),
                    icon: Icon(Icons.favorite, color: Colors.green),
                  ),
                  ButtonSegment(
                    value: StudentRelationType.enmity,
                    label: Text('Inimicizia'),
                    icon: Icon(Icons.warning, color: Colors.red),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (value) =>
                    setDialogState(() => type = value.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: firstId == null || secondId == null
                  ? null
                  : () async {
                      await repository.save(
                        firstId: firstId!,
                        secondId: secondId!,
                        type: type,
                        classUniqueCode: classCode,
                      );
                      if (context.mounted) Navigator.pop(context, true);
                    },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
    if (result == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final classDetails = ref.watch(currentClassDetailsProvider);
    final studentsAsync = ref.watch(currentClassStudentsSyncProvider);
    final classCode = classDetails?.uniqueCode ?? '';
    final relationsAsync = ref.watch(
      _studentRelationsByClassProvider(classCode),
    );

    return AppScaffold(
      title: 'GRAFICO RAPPORTI',
      child: studentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Errore: $error')),
        data: (students) => relationsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Errore rapporti: $error')),
          data: (relations) =>
              _buildGraph(context, students, relations, classCode),
        ),
      ),
    );
  }

  Widget _buildGraph(
    BuildContext context,
    List<Student> students,
    List<StudentRelation> relations,
    String classCode,
  ) {
    final classDetails = ref.read(currentClassDetailsProvider);
    final size = MediaQuery.sizeOf(context);
    return Column(
      children: [
        Expanded(
          child: RepaintBoundary(
            key: _graphKey,
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              width: size.width,
              height: size.height,
              child: CustomPaint(
                painter: _RelationsPainter(
                  students: students,
                  relations: relations,
                ),
                child: Center(
                  child: Text(
                    'GRAFICO RAPPORTI ${classDetails?.name ?? ''}'.trim(),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      _editRelation(context, students, null, classCode),
                  icon: const Icon(Icons.add),
                  label: const Text('Nuovo rapporto'),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<bool>(
                tooltip: 'Esporta grafo',
                icon: const Icon(Icons.ios_share),
                onSelected: (jpeg) => _exportGraph(
                  className: classDetails?.name ?? '',
                  jpeg: jpeg,
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: false, child: Text('Esporta PNG')),
                  PopupMenuItem(value: true, child: Text('Esporta JPG')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RelationsPainter extends CustomPainter {
  final List<Student> students;
  final List<StudentRelation> relations;

  const _RelationsPainter({required this.students, required this.relations});

  @override
  void paint(Canvas canvas, Size size) {
    if (students.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.32;
    final positions = <String, Offset>{};
    for (var i = 0; i < students.length; i++) {
      final angle = (i / students.length) * 6.283185307;
      positions[students[i].id] =
          center + Offset(radius * math.cos(angle), radius * math.sin(angle));
    }
    for (final relation in relations) {
      final a = positions[relation.studentAId];
      final b = positions[relation.studentBId];
      if (a == null || b == null) continue;
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = relation.type == StudentRelationType.enmity
              ? Colors.red
              : Colors.green
          ..strokeWidth = 3,
      );
    }
    for (final student in students) {
      final position = positions[student.id]!;
      canvas.drawCircle(position, 27, Paint()..color = const Color(0xFF174A7E));
      final label = '${student.surname}\n${student.name}';
      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 75);
      text.paint(canvas, position - Offset(text.width / 2, text.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RelationsPainter oldDelegate) =>
      oldDelegate.students != students || oldDelegate.relations != relations;
}

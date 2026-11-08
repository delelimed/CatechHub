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
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
    required bool asPdf,
  }) async {
    final boundary =
        _graphKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final pngBytes = await boundary.toImage(pixelRatio: 3).then((image) async {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final bytes = asPdf
        ? Uint8List.fromList(
            await (pw.Document()..addPage(
                  pw.Page(
                    pageFormat: PdfPageFormat.a4.landscape,
                    margin: pw.EdgeInsets.zero,
                    build: (_) => pw.Image(pw.MemoryImage(pngBytes)),
                  ),
                ))
                .save(),
          )
        : Uint8List.fromList(
            image.encodeJpg(image.decodePng(pngBytes)!, quality: 92),
          );
    final directory = await getTemporaryDirectory();
    final extension = asPdf ? 'pdf' : 'jpg';
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
    final studentIds = students.map((student) => student.id).toSet();
    var firstId = studentIds.contains(existing?.studentAId)
        ? existing?.studentAId
        : (studentIds.contains(widget.focusStudentId)
              ? widget.focusStudentId
              : null);
    var secondId = studentIds.contains(existing?.studentBId)
        ? existing?.studentBId
        : null;
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
                      try {
                        await repository.save(
                          firstId: firstId!,
                          secondId: secondId!,
                          type: type,
                          classUniqueCode: classCode,
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      } on ArgumentError catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.message)),
                          );
                        }
                      }
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
    final availableSize = MediaQuery.sizeOf(context);
    final graphWidth = availableSize.width;
    final graphHeight = graphWidth * 210 / 297;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: RepaintBoundary(
                key: _graphKey,
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  width: graphWidth,
                  height: graphHeight,
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    children: [
                      Text(
                        'GRAFICO RAPPORTI ${classDetails?.name ?? ''}'.trim(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: CustomPaint(
                          painter: _RelationsPainter(
                            students: students,
                            relations: relations,
                            edgeBackground: Theme.of(context)
                                .colorScheme
                                .surface,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
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
                  asPdf: !jpeg,
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: false, child: Text('Esporta PDF')),
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
  final Color edgeBackground;

  const _RelationsPainter({
    required this.students,
    required this.relations,
    required this.edgeBackground,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (students.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    const nodeRadius = 28.0;
    const nodeGap = 18.0;
    final maxRadius = math.max(
      nodeRadius,
      size.shortestSide / 2 - nodeRadius - 12,
    );
    final minimumNodeDistance = nodeRadius * 2 + nodeGap;
    final ringCount = _ringCount(
      students.length,
      maxRadius,
      minimumNodeDistance,
    );
    final positions = <String, Offset>{};
    var studentIndex = 0;
    for (var ring = 0; ring < ringCount; ring++) {
      final radius = maxRadius * (ring + 1) / ringCount;
      final remaining = students.length - studentIndex;
      final ringsLeft = ringCount - ring;
      final capacity = _ringCapacity(radius, minimumNodeDistance);
      final count = ring == ringCount - 1
          ? remaining
          : math.min(capacity, (remaining / ringsLeft).ceil());
      for (var index = 0; index < count; index++) {
        final angle =
            -math.pi / 2 +
            (index / count) * 2 * math.pi +
            (ring.isEven ? 0 : math.pi / count);
        positions[students[studentIndex].id] =
            center + Offset(radius * math.cos(angle), radius * math.sin(angle));
        studentIndex++;
      }
    }
    for (final relation in relations) {
      final a = positions[relation.studentAId];
      final b = positions[relation.studentBId];
      if (a == null || b == null) continue;
      final direction = b - a;
      final distance = direction.distance;
      if (distance <= nodeRadius * 2) continue;
      final unit = direction / distance;
      final color = relation.type == StudentRelationType.enmity
          ? Colors.red.shade700
          : Colors.green.shade700;
      canvas.drawLine(
        a + unit * nodeRadius,
        b - unit * nodeRadius,
        Paint()
          ..color = edgeBackground
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        a + unit * nodeRadius,
        b - unit * nodeRadius,
        Paint()
          ..color = color
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }
    for (final student in students) {
      final position = positions[student.id]!;
      canvas
        ..drawCircle(position, nodeRadius + 2, Paint()..color = Colors.white)
        ..drawCircle(
          position,
          nodeRadius,
          Paint()..color = const Color(0xFF174A7E),
        );
      final label = '${student.surname}\n${student.name}';
      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: nodeRadius * 2 - 8);
      text.paint(canvas, position - Offset(text.width / 2, text.height / 2));
    }
  }

  int _ringCount(int nodeCount, double maxRadius, double minDistance) {
    for (var rings = 1; rings <= nodeCount; rings++) {
      var capacity = 0;
      for (var ring = 1; ring <= rings; ring++) {
        capacity += _ringCapacity(maxRadius * ring / rings, minDistance);
      }
      if (capacity >= nodeCount) return rings;
    }
    return nodeCount;
  }

  int _ringCapacity(double radius, double minDistance) {
    if (radius <= 0) return 1;
    return math.max(1, (2 * math.pi * radius / minDistance).floor());
  }

  @override
  bool shouldRepaint(covariant _RelationsPainter oldDelegate) =>
      oldDelegate.students != students || oldDelegate.relations != relations;
}

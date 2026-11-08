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

import '../../core/providers/current_class_provider.dart';
import '../../shared/models/student_model.dart';
import '../../shared/models/student_relation_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'student_relations_repository.dart';
import 'students_repository.dart';

final _studentRelationsByClassProvider = StreamProvider.autoDispose
    .family<List<StudentRelation>, String>((ref, classCode) {
      return ref
          .read(studentRelationsRepositoryProvider)
          .watchByClass(classCode);
    });

final _allStudentsProvider = StreamProvider.autoDispose<List<Student>>((ref) {
  return ref.read(studentsRepositoryProvider).getAllStudents();
});

enum _RelationFilter { all, student, friendships, enmities }

class StudentRelationsPage extends ConsumerStatefulWidget {
  final String? focusStudentId;
  final String? focusStudentClassId;
  final String? focusStudentClassUniqueCode;

  const StudentRelationsPage({
    super.key,
    this.focusStudentId,
    this.focusStudentClassId,
    this.focusStudentClassUniqueCode,
  });

  @override
  ConsumerState<StudentRelationsPage> createState() =>
      _StudentRelationsPageState();
}

class _StudentRelationsPageState extends ConsumerState<StudentRelationsPage> {
  final _graphKey = GlobalKey();
  final _graphTransformationController = TransformationController();
  _RelationFilter _relationFilter = _RelationFilter.all;
  String? _selectedStudentId;

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
    final selectableStudents = {
      for (final student in students) student.id: student,
    }.values.toList();
    final studentIds = selectableStudents.map((student) => student.id).toSet();
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
                items: selectableStudents
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
                items: selectableStudents
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
  void dispose() {
    _graphTransformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final classDetails = ref.watch(currentClassDetailsProvider);
    final allStudentsAsync = ref.watch(_allStudentsProvider);
    final currentClassId = ref.watch(currentClassProvider) ?? '';
    final classId = currentClassId.isNotEmpty
        ? currentClassId
        : (widget.focusStudentClassId ?? '');
    final rosterIds = classDetails?.id == classId
        ? classDetails!.studentIds.toSet()
        : <String>{};
    final classCode =
        classDetails?.id == classId &&
            (classDetails?.uniqueCode.isNotEmpty ?? false)
        ? classDetails!.uniqueCode
        : (widget.focusStudentClassUniqueCode ?? '');
    final relationsAsync = ref.watch(
      _studentRelationsByClassProvider(classCode),
    );

    return AppScaffold(
      title: 'GRAFICO RAPPORTI',
      child: allStudentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Errore: $error')),
        data: (allStudents) {
          final students = allStudents
              .where(
                (student) =>
                    student.classId == classId ||
                    rosterIds.contains(student.id) ||
                    student.id == widget.focusStudentId,
              )
              .toList();
          return relationsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Errore rapporti: $error')),
            data: (relations) => _buildGraph(
              context,
              students,
              relations,
              classCode,
              classDetails?.name ?? '',
            ),
          );
        },
      ),
    );
  }

  Widget _buildGraph(
    BuildContext context,
    List<Student> students,
    List<StudentRelation> relations,
    String classCode,
    String className,
  ) {
    final visibleRelations = relations.where((relation) {
      switch (_relationFilter) {
        case _RelationFilter.all:
        case _RelationFilter.student:
          return _relationFilter == _RelationFilter.all ||
              relation.studentAId == _selectedStudentId ||
              relation.studentBId == _selectedStudentId;
        case _RelationFilter.friendships:
          return relation.type == StudentRelationType.friendship;
        case _RelationFilter.enmities:
          return relation.type == StudentRelationType.enmity;
      }
    }).toList();
    final Set<String>? visibleStudentIds;
    if (_relationFilter == _RelationFilter.all) {
      visibleStudentIds = null;
    } else {
      visibleStudentIds = visibleRelations
          .expand((relation) => [relation.studentAId, relation.studentBId])
          .toSet();
      if (_relationFilter == _RelationFilter.student &&
          _selectedStudentId != null) {
        visibleStudentIds.add(_selectedStudentId!);
      }
    }
    final visibleStudents = visibleStudentIds == null
        ? students
        : students
              .where((student) => visibleStudentIds!.contains(student.id))
              .toList();
    final availableSize = MediaQuery.sizeOf(context);
    final columns = math.max(1, math.sqrt(visibleStudents.length).ceil());
    final rows = (visibleStudents.length / columns).ceil();
    const cellSize = 88.0;
    final graphWidth = math.max(
      availableSize.width - 32,
      columns * cellSize + 48,
    );
    final graphHeight = math.max(
      availableSize.height - 180,
      rows * cellSize + 100,
    );
    return Column(
      children: [
        _buildGraphFilters(students),
        Expanded(
          child: InteractiveViewer(
            transformationController: _graphTransformationController,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(160),
            minScale: 0.35,
            maxScale: 2.5,
            child: RepaintBoundary(
              key: _graphKey,
              child: Container(
                color: Colors.white,
                width: graphWidth,
                height: graphHeight,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  children: [
                    Text(
                      'GRAFICO RAPPORTI $className'.trim(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: CustomPaint(
                        painter: _RelationsPainter(
                          students: visibleStudents,
                          relations: visibleRelations,
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.pan_tool_outlined, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Trascina per spostarti; usa due dita per zoomare'),
              ),
              IconButton(
                tooltip: 'Riduci',
                onPressed: () => _changeGraphScale(0.8),
                icon: const Icon(Icons.zoom_out),
              ),
              IconButton(
                tooltip: 'Ingrandisci',
                onPressed: () => _changeGraphScale(1.25),
                icon: const Icon(Icons.zoom_in),
              ),
              IconButton(
                tooltip: 'Reimposta vista',
                onPressed: _resetGraphView,
                icon: const Icon(Icons.center_focus_strong),
              ),
            ],
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
                onSelected: (jpeg) =>
                    _exportGraph(className: className, asPdf: !jpeg),
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

  Widget _buildGraphFilters(List<Student> students) {
    final sortedStudents = [...students]
      ..sort((a, b) {
        final surname = a.surname.toLowerCase().compareTo(
          b.surname.toLowerCase(),
        );
        return surname != 0
            ? surname
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final selectedStudentIsValid = sortedStudents.any(
      (student) => student.id == _selectedStudentId,
    );
    if (!selectedStudentIsValid) _selectedStudentId = null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<_RelationFilter>(
            value: _relationFilter,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(
                value: _RelationFilter.all,
                child: Text('Tutti i rapporti'),
              ),
              DropdownMenuItem(
                value: _RelationFilter.student,
                child: Text('Un ragazzo'),
              ),
              DropdownMenuItem(
                value: _RelationFilter.friendships,
                child: Text('Solo amicizie'),
              ),
              DropdownMenuItem(
                value: _RelationFilter.enmities,
                child: Text('Solo inimicizie'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _relationFilter = value);
            },
          ),
          if (_relationFilter == _RelationFilter.student)
            DropdownButton<String>(
              value: _selectedStudentId,
              hint: const Text('Scegli ragazzo'),
              underline: const SizedBox.shrink(),
              items: sortedStudents
                  .map(
                    (student) => DropdownMenuItem(
                      value: student.id,
                      child: Text('${student.surname} ${student.name}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedStudentId = value),
            ),
        ],
      ),
    );
  }

  void _changeGraphScale(double factor) {
    final currentScale = _graphTransformationController.value
        .getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(0.35, 2.5);
    final scaleFactor = nextScale / currentScale;
    _graphTransformationController.value = Matrix4.identity()
      ..scaleByDouble(scaleFactor, scaleFactor, scaleFactor, 1.0)
      ..multiply(_graphTransformationController.value);
  }

  void _resetGraphView() {
    _graphTransformationController.value = Matrix4.identity();
  }
}

class _RelationsPainter extends CustomPainter {
  final List<Student> students;
  final List<StudentRelation> relations;

  const _RelationsPainter({required this.students, required this.relations});

  @override
  void paint(Canvas canvas, Size size) {
    if (students.isEmpty) return;
    const nodeRadius = 28.0;
    const cellSize = 88.0;
    final columns = math.max(1, math.sqrt(students.length).ceil());
    final gridWidth = (columns - 1) * cellSize;
    final startX = (size.width - gridWidth) / 2;
    final startY = math.min(cellSize / 2, size.height / 2);
    final positions = <String, Offset>{};
    for (var index = 0; index < students.length; index++) {
      final row = index ~/ columns;
      final column = index % columns;
      positions[students[index].id] = Offset(
        startX + column * cellSize,
        startY + row * cellSize,
      );
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
          ..color = Colors.black87
          ..strokeWidth = 11
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        a + unit * nodeRadius,
        b - unit * nodeRadius,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 7
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

  @override
  bool shouldRepaint(covariant _RelationsPainter oldDelegate) =>
      oldDelegate.students != students || oldDelegate.relations != relations;
}

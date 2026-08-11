// ─────────────────────────────────────────────────────────────────────────
// create_substitute_delegation_page.dart — creazione supplenza (Titolare)
// ─────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_service.dart';
import '../../core/providers/current_class_provider.dart';
import '../../core/storage/local_database.dart';
import '../../features/sync/p2p/p2p_security_service.dart';
import '../../shared/models/class_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/qr_chunks_dialog.dart';
import 'substitute_providers.dart';

class CreateSubstituteDelegationPage extends ConsumerStatefulWidget {
  const CreateSubstituteDelegationPage({super.key});

  @override
  ConsumerState<CreateSubstituteDelegationPage> createState() =>
      _CreateSubstituteDelegationPageState();
}

class _CreateSubstituteDelegationPageState
    extends ConsumerState<CreateSubstituteDelegationPage> {
  final _security = P2PSecurityService();

  SchoolClass? _class;
  P2PDeviceAssociation? _substitute;
  DateTime _validFrom = DateTime.now();
  DateTime _validUntil = DateTime.now().add(const Duration(days: 7));
  bool _loadingAssociations = true;
  bool _creating = false;
  List<P2PDeviceAssociation> _associations = [];

  @override
  void initState() {
    super.initState();
    _loadAssociations();
  }

  Future<void> _loadAssociations() async {
    final list = await _security.getAllAssociations();
    if (!mounted) return;
    setState(() {
      _associations = list;
      _loadingAssociations = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final classes = ref.watch(myClassesProvider);
    return AppScaffold(
      title: 'Nuova supplenza',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _pickerTile(
            icon: Icons.school_rounded,
            label: 'Classe',
            value: _class?.name,
            placeholder: 'Seleziona una classe',
            onTap: () => _pickClass(classes),
          ),
          const SizedBox(height: 14),
          _pickerTile(
            icon: Icons.person_rounded,
            label: 'Supplente',
            value: _substitute?.deviceName,
            placeholder: _loadingAssociations
                ? 'Caricamento dispositivi…'
                : 'Seleziona un catechista',
            onTap: _loadingAssociations ? null : _pickSubstitute,
          ),
          const SizedBox(height: 14),
          _dateRow(),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _creating || _class == null || _substitute == null
                ? null
                : _create,
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('Genera QR di delega'),
          ),
        ],
      ),
    );
  }

  // ─── Selezione classe ──────────────────────────────────────────────────
  Future<void> _pickClass(List<SchoolClass> classes) async {
    if (classes.isEmpty) {
      _snack('Nessuna classe di tua appartenenza.');
      return;
    }
    final picked = await showDialog<SchoolClass>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Scegli la classe'),
        children: classes
            .map(
              (c) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c),
                child: Text(c.name),
              ),
            )
            .toList(),
      ),
    );
    if (picked != null && mounted) setState(() => _class = picked);
  }

  // ─── Selezione supplente ───────────────────────────────────────────────
  Future<void> _pickSubstitute() async {
    if (_associations.isEmpty) {
      _snack('Nessun dispositivo associato. Associa prima un altro '
          'catechista nelle Impostazioni.');
      return;
    }
    final picked = await showDialog<P2PDeviceAssociation>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Scegli il Supplente'),
        children: _associations
            .map(
              (a) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, a),
                child: Text(a.deviceName),
              ),
            )
            .toList(),
      ),
    );
    if (picked != null && mounted) setState(() => _substitute = picked);
  }

  // ─── Date ──────────────────────────────────────────────────────────────
  Widget _dateRow() {
    return Row(
      children: [
        Expanded(
          child: _pickerTile(
            icon: Icons.event_rounded,
            label: 'Dal',
            value: DateFormat('dd/MM/yyyy', 'it_IT').format(_validFrom),
            placeholder: 'Data inizio',
            onTap: _pickValidFrom,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _pickerTile(
            icon: Icons.event_rounded,
            label: 'Al',
            value: DateFormat('dd/MM/yyyy', 'it_IT').format(_validUntil),
            placeholder: 'Data fine',
            onTap: _pickValidUntil,
          ),
        ),
      ],
    );
  }

  Future<void> _pickValidFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _validFrom,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _validFrom = picked;
        if (_validUntil.isBefore(picked)) {
          _validUntil = picked.add(const Duration(days: 7));
        }
      });
    }
  }

  Future<void> _pickValidUntil() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _validUntil,
      firstDate: _validFrom,
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null && mounted) setState(() => _validUntil = picked);
  }

  // ─── Creazione ─────────────────────────────────────────────────────────
  Future<void> _create() async {
    final schoolClass = _class;
    final substitute = _substitute;
    if (schoolClass == null || substitute == null) return;

    setState(() => _creating = true);
    try {
      final students = _loadStudents(schoolClass);
      final service = ref.read(substituteDelegationServiceProvider);
      final (delegation, chunks) = await service.createDelegation(
        classId: schoolClass.id,
        classUniqueCode: schoolClass.uniqueCode,
        className: schoolClass.name,
        students: students,
        ownerCatechistId: AuthService.getCatechistId(),
        ownerName: _localName(),
        substituteCatechistId: substitute.catechistId ?? substitute.deviceId,
        substituteName: substitute.deviceName,
        substituteDeviceId: substitute.deviceId,
        substitutePublicKeyBase64: substitute.publicKeyBase64,
        validFrom: _validFrom,
        validUntil: _validUntil,
      );

      final repo = ref.read(substituteDelegationRepoProvider);
      await repo.save(delegation.copyWith(qrChunks: chunks));

      if (!mounted) return;
      await QrChunksDialog.show(
        context,
        title: 'QR di delega',
        subtitle:
            'Delega della classe "${schoolClass.name}" a '
            '${substitute.deviceName}.\nIl Supplente deve inquadrarli in '
            'ordine con "Scansiona QR".',
        chunks: chunks,
        footer: 'Conservati questi QR: servono come backup della delega.',
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        _snack('Creazione non riuscita: $e');
      }
    }
  }

  List<Map<String, String>> _loadStudents(SchoolClass schoolClass) {
    final box = LocalDatabase.students();
    final result = <Map<String, String>>[];
    for (final id in schoolClass.studentIds) {
      final raw = box.get(id);
      if (raw == null) continue;
      final map = LocalDatabase.toStringDynamicMap(raw);
      result.add({
        'id': id,
        'name': map['name']?.toString() ?? '',
        'surname': map['surname']?.toString() ?? '',
      });
    }
    return result;
  }

  String _localName() {
    final box = LocalDatabase.auth();
    final first = box.get('first_name', defaultValue: '') as String? ?? '';
    final last = box.get('last_name', defaultValue: '') as String? ?? '';
    final name = '$first $last'.trim();
    return name.isEmpty ? AuthService.localUserName : name;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

Widget _pickerTile({
  required IconData icon,
  required String label,
  required String? value,
  required String placeholder,
  required VoidCallback? onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value ?? placeholder,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: value == null ? Colors.grey.shade500 : null,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        ],
      ),
    ),
  );
}

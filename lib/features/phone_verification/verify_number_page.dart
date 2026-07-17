/// Pagina di verifica numeri di telefono per CateREG.
///
/// Questa schermata consente agli operatori di cercare un numero di telefono
/// nell'anagrafica studenti e visualizzare i relativi abbinamenti (studente,
/// madre, padre). È pensata per supportare la comunicazione tramite WhatsApp
/// con le famiglie: l'operatore può chiamare o avviare una chat WhatsApp
/// direttamente dal risultato della ricerca.
///
/// CateREG è un gestionale per centri catechistici parrocchiali che tiene
/// traccia degli studenti iscritti, dei loro genitori e dei relativi
/// recapiti telefonici. Questa pagina è cruciale per aggiornare e verificare
/// i contatti telefonici prima di inviare comunicazioni di gruppo.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

//import '../../shared/models/student_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../students/students_repository.dart';

/// Provider del repository studenti, usato per interrogare l'anagrafica.
final studentsRepoProvider = Provider((ref) => StudentsRepository());

/// Schermata principale di verifica numeri di telefono.
///
/// Widget [ConsumerStatefulWidget] che ospita la ricerca di un recapito
/// telefonico nel database studenti. L'utente digita un numero, la pagina
/// interroga il repository e mostra tutti gli abbinamenti trovati tra
/// studenti e genitori, offrendo azioni rapide (chiamata / WhatsApp).
class VerifyNumberPage extends ConsumerStatefulWidget {
  const VerifyNumberPage({super.key});

  @override
  ConsumerState<VerifyNumberPage> createState() => _VerifyNumberPageState();
}

/// Stato interno di [VerifyNumberPage].
///
/// Mantiene il controller del campo di ricerca, l'elenco dei risultati
/// trovati e un flag che indica se è in corso una query sul repository.
class _VerifyNumberPageState extends ConsumerState<VerifyNumberPage> {
  /// Controller per il campo di input del numero di telefono.
  final _phoneController = TextEditingController();

  /// Elenco degli abbinamenti trovati dall'ultima ricerca.
  final List<PhoneMatch> _matches = [];

  /// Indica se è in corso una ricerca nel repository studenti.
  bool _isSearching = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  /// Avvia la ricerca nel database studenti.
  ///
  /// Normalizza il numero inserito, interroga il repository e confronta
  /// ogni studente sui tre campi telefono (studente, madre, padre).
  /// I risultati vengono aggiunti a [_matches] e la UI viene aggiornata.
  Future<void> _searchNumber() async {
    final phoneNumber = _phoneController.text.trim();
    if (phoneNumber.isEmpty) return;

    setState(() {
      _isSearching = true;
      _matches.clear();
    });

    final repo = ref.read(studentsRepoProvider);
    final allStudents = await repo.getAllStudents().first;

    final foundMatches = <PhoneMatch>[];

    for (final student in allStudents) {
      // Normalizza i numeri per il confronto (rimuovi spazi, trattini, ecc.)
      final searchNumber = _normalizePhone(phoneNumber);
      
      // Controlla numero studente
      if (student.studentPhone.isNotEmpty) {
        final studentPhone = _normalizePhone(student.studentPhone);
        if (studentPhone.contains(searchNumber) || searchNumber.contains(studentPhone)) {
          foundMatches.add(PhoneMatch(
            type: PhoneMatchType.student,
            name: '${student.name} ${student.surname}',
            phone: student.studentPhone,
            studentId: student.id,
          ));
        }
      }

      // Controlla numero madre
      if (student.motherPhone.isNotEmpty) {
        final motherPhone = _normalizePhone(student.motherPhone);
        if (motherPhone.contains(searchNumber) || searchNumber.contains(motherPhone)) {
          foundMatches.add(PhoneMatch(
            type: PhoneMatchType.mother,
            name: '${student.motherName} ${student.motherSurname}',
            phone: student.motherPhone,
            studentName: '${student.name} ${student.surname}',
            studentId: student.id,
          ));
        }
      }

      // Controlla numero padre
      if (student.fatherPhone.isNotEmpty) {
        final fatherPhone = _normalizePhone(student.fatherPhone);
        if (fatherPhone.contains(searchNumber) || searchNumber.contains(fatherPhone)) {
          foundMatches.add(PhoneMatch(
            type: PhoneMatchType.father,
            name: '${student.fatherName} ${student.fatherSurname}',
            phone: student.fatherPhone,
            studentName: '${student.name} ${student.surname}',
            studentId: student.id,
          ));
        }
      }
    }

    setState(() {
      _isSearching = false;
      _matches.addAll(foundMatches);
    });
  }

  /// Normalizza un numero di telefono rimuovendo tutto ciò che non è cifra.
  ///
  /// Utile per il confronto tra numeri formattati diversamente
  /// (es. "333 123 4567" vs "3331234567").
  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Avvia una chiamata telefonica verso il numero specificato.
  ///
  /// Utilizza [launchUrl] con schema `tel:` per delegare al dialer di sistema.
  Future<void> _callNumber(String phone) async {
    final uri = Uri.parse('tel:$phone');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Avvia una chat WhatsApp verso il numero specificato.
  ///
  /// Normalizza il numero e costruisce l'URL `https://wa.me/<numero>`
  /// per aprire WhatsApp con il numero già precompilato.
  Future<void> _whatsappNumber(String phone) async {
    final normalized = _normalizePhone(phone);
    final uri = Uri.parse('https://wa.me/$normalized');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Costruisce l'interfaccia della pagina.
  ///
  /// Mostra una card di ricerca in alto; se ci sono risultati li elenca
  /// con [_MatchCard], altrimenti mostra un messaggio di nessun risultato.
  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Verifica Numero',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SearchCard(
              controller: _phoneController,
              isSearching: _isSearching,
              onSearch: _searchNumber,
            ),
            const SizedBox(height: 20),
            if (_matches.isNotEmpty) ...[
              Text(
                'Risultati (${_matches.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF174A7E),
                ),
              ),
              const SizedBox(height: 12),
              ..._matches.map((match) => _MatchCard(
                match: match,
                onCall: () => _callNumber(match.phone),
                onWhatsapp: () => _whatsappNumber(match.phone),
              )),
            ] else if (!_isSearching && _phoneController.text.isNotEmpty)
              _EmptyResult(),
          ],
        ),
      ),
    );
  }
}

/// Card di input per la ricerca del numero di telefono.
///
/// Contiene un [TextField] con tastiera telefonica e un pulsante "Cerca".
/// Mostra un indicatore di caricamento quando la ricerca è in corso.
class _SearchCard extends StatelessWidget {
  /// Controller per il campo di inserimento del numero.
  final TextEditingController controller;

  /// Indica se la ricerca è in corso (mostra spinner e disabilita il pulsante).
  final bool isSearching;

  /// Callback invocata quando l'utente preme "Cerca".
  final VoidCallback onSearch;

  const _SearchCard({
    required this.controller,
    required this.isSearching,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Inserisci numero di telefono',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: 'es. 3331234567',
              prefixIcon: const Icon(Icons.phone_rounded),
              suffixIcon: isSearching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF174A7E)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isSearching ? null : onSearch,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(isSearching ? 'Ricerca in corso...' : 'Cerca'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card che visualizza un singolo abbinamento trovato.
///
/// Mostra il nome della persona, il numero di telefono e, se si tratta
/// di un genitore, lo studente associato. Offre due pulsanti di azione:
/// chiamata telefonica e apertura chat WhatsApp.
class _MatchCard extends StatelessWidget {
  /// Dati dell'abbinamento da visualizzare.
  final PhoneMatch match;

  /// Callback per avviare una chiamata al numero trovato.
  final VoidCallback onCall;

  /// Callback per aprire WhatsApp con il numero trovato.
  final VoidCallback onWhatsapp;

  const _MatchCard({
    required this.match,
    required this.onCall,
    required this.onWhatsapp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: _getMatchColor(match.type).withValues(alpha: 0.1),
          child: Icon(
            _getMatchIcon(match.type),
            color: _getMatchColor(match.type),
          ),
        ),
        title: Text(
          match.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF174A7E),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              match.phone,
              style: const TextStyle(color: Colors.grey),
            ),
            if (match.studentName != null) ...[
              const SizedBox(height: 4),
              Text(
                'Genitore di: ${match.studentName}',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.phone, color: Colors.green),
              onPressed: onCall,
              tooltip: 'Chiama',
            ),
            IconButton(
              icon: const Icon(Icons.message, color: Colors.green),
              onPressed: onWhatsapp,
              tooltip: 'WhatsApp',
            ),
          ],
        ),
      ),
    );
  }

  /// Restituisce il colore associato al tipo di abbinamento:
  /// blu per lo studente, rosa per la madre, indaco per il padre.
  Color _getMatchColor(PhoneMatchType type) {
    switch (type) {
      case PhoneMatchType.student:
        return Colors.blue;
      case PhoneMatchType.mother:
        return Colors.pink;
      case PhoneMatchType.father:
        return Colors.indigo;
    }
  }

  /// Restituisce l'icona appropriata per il tipo di abbinamento:
  /// persona per lo studente, donna per la madre, uomo per il padre.
  IconData _getMatchIcon(PhoneMatchType type) {
    switch (type) {
      case PhoneMatchType.student:
        return Icons.person_rounded;
      case PhoneMatchType.mother:
        return Icons.woman_rounded;
      case PhoneMatchType.father:
        return Icons.man_rounded;
    }
  }
}

/// Widget mostrato quando la ricerca non produce alcun risultato.
///
/// Esibisce un'icona di ricerca vuota e un messaggio che invita
/// l'operatore a provare con un numero diverso.
class _EmptyResult extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Nessun risultato trovato',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Prova con un altro numero di telefono',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tipologia di abbinamento telefonico.
///
/// Distingue se il numero appartiene direttamente allo studente,
/// alla madre o al padre.
enum PhoneMatchType {
  /// Numero dello studente stesso.
  student,

  /// Numero della madre.
  mother,

  /// Numero del padre.
  father,
}

/// Modello dati che rappresenta un abbinamento trovato tra un numero
/// di telefono e un soggetto nell'anagrafica.
///
/// Contiene il tipo di relazione (studente/genitore), il nome della
/// persona, il recapito e, opzionalmente, il nome dello studente
/// associato (quando il match riguarda un genitore).
class PhoneMatch {
  /// Tipo di abbinamento (studente, madre, padre).
  final PhoneMatchType type;

  /// Nome della persona abbinata.
  final String name;

  /// Numero di telefono corrispondente.
  final String phone;

  /// Nome dello studente associato (solo per i genitori).
  final String? studentName;

  /// ID dello studente associato.
  final String? studentId;

  PhoneMatch({
    required this.type,
    required this.name,
    required this.phone,
    this.studentName,
    this.studentId,
  });
}
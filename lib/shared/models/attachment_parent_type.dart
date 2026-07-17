// ══════════════════════════════════════════════════════════════════════════════
// attachment_parent_type.dart — CatechHub (costanti tipi entità allegati)
//
// Definisce le costanti per i tipi di entità proprietarie di allegati.
// Ogni Attachment.parentType deve corrispondere a uno di questi valori.
//
// CONTESTO PROGETTO:
//   Il sistema allegati è polimorfico: uno stesso Attachment può essere
//   associato a Student, PlanningMeeting o Catechesi. Il campo
//   parentType discrimina l'entità proprietaria. Queste costanti
//   centralizzano i valori ammessi per evitare typo e garantire
//   coerenza tra AttachmentModel, AttachmentRepository e le varie UI.
//
// USO:
//   AttachmentParentType.student  → per allegati dello studente
//   AttachmentParentType.meeting  → per allegati dell'incontro
//   AttachmentParentType.catechesi → per allegati della catechesi
// ══════════════════════════════════════════════════════════════════════════════

class AttachmentParentType {
  /// Allegato associato a uno studente (es. foto, certificato).
  static const student = 'student';

  /// Allegato associato a un incontro (es. materiale didattico).
  static const meeting = 'meeting';

  /// Allegato associato a un contenuto catechetico (es. foto, scheda).
  static const catechesi = 'catechesi';
}

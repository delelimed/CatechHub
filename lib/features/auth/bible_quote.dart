/// Modello che rappresenta un versetto biblico con il suo testo e riferimento.
///
/// Utilizzato nella schermata di login per mostrare un versetto casuale che
/// offra ispirazione e richiami il fondamento spirituale dell'app CatechHub.
/// I versetti sono stati selezionati a tema catechetico: insegnamento,
/// comunione, amore fraterno e perseveranza.
class BibleQuote {
  final String text;
  final String reference;

  const BibleQuote({required this.text, required this.reference});
}

/// Raccolta di versetti biblici a tema catechetico.
///
/// Ogni citazione viene selezionata casualmente al caricamento della
/// [LoginPage] per accompagnare l'utente con un messaggio di fede durante
/// l'accesso o la configurazione iniziale del profilo.
/// I riferimenti coprono brani chiave legati all'insegnamento (Matteo 28,20),
/// all'amore fraterno (Giovanni 15,12) e alla forza nella fede (Filippesi 4,13).
const List<BibleQuote> bibleQuotes = [
  BibleQuote(
    text: "Dove sono due o tre riuniti nel mio nome, io sono in mezzo a loro.",
    reference: "Matteo 18,20",
  ),
  BibleQuote(
    text: "Io sono con voi tutti i giorni, fino alla fine del mondo.",
    reference: "Matteo 28,20",
  ),
  BibleQuote(
    text: "Lasciate che i bambini vengano a me.",
    reference: "Marco 10,14",
  ),
  BibleQuote(
    text: "Tutto posso in colui che mi dà forza.",
    reference: "Filippesi 4,13",
  ),
  BibleQuote(
    text: "La gioia del Signore è la vostra forza.",
    reference: "Neemia 8,10",
  ),
  BibleQuote(
    text: "Siate tutti concordi, compassionevoli, amarvi come fratelli, indulgenti, umili.",
    reference: "1 Pietro 3,8",
  ),
  BibleQuote(
    text: "Insegnate a osservare tutte le cose che vi ho comandato.",
    reference: "Matteo 28,20",
  ),
  BibleQuote(
    text: "Il mio comandamento è questo: che vi amiate gli uni gli altri, come io ho amato voi.",
    reference: "Giovanni 15,12",
  ),
  BibleQuote(
    text: "Ecco, come il padre mi ha amato, anche io ho amato voi; state nel mio amore.",
    reference: "Giovanni 15,9",
  ),
  BibleQuote(
    text: "Che la parola di Cristo abiti in voi riccamente; ammaestratevi e esortatevi a vicenda con ogni sapienza.",
    reference: "Colossesi 3,16",
  ),
  BibleQuote(
    text: "Lampada per i miei passi è la tua parola, luce sul mio cammino.",
    reference: "Salmi 119,105",
  ),
  BibleQuote(
    text: "Andate in tutto il mondo e proclamate il Vangelo a ogni creatura.",
    reference: "Marco 16,15",
  ),
  BibleQuote(
    text: "Crescete nella grazia e nella conoscenza del Signore nostro e Salvatore Gesù Cristo.",
    reference: "2 Pietro 3,18",
  ),
  BibleQuote(
    text: "Non sono io che vi ho comandato: 'Siate forti e coraggiosi'? Non temere e non spaventarti, perché il Signore, tuo Dio, è con te dovunque tu vada.",
    reference: "Giosuè 1,9",
  ),
  BibleQuote(
    text: "La fede dipende dalla predicazione e la predicazione a sua volta si attua per mezzo della parola di Cristo.",
    reference: "Romani 10,17",
  ),
];

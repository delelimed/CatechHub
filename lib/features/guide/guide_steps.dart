import 'package:flutter/material.dart';

class GuideStep {
  final IconData icon;
  final String title;
  final String description;
  final String? demoRoute;

  const GuideStep({
    required this.icon,
    required this.title,
    required this.description,
    this.demoRoute,
  });
}

List<GuideStep> catechistGuideSteps() => const [
  GuideStep(
    icon: Icons.waving_hand_rounded,
    title: 'Benvenuto in CatechHub',
    description:
        'Questa è una guida rapida alle funzioni principali.\n'
        'Per i primi passi vedrai alcuni dati di esempio: '
        'verranno rimossi automaticamente al riavvio dell\'app.',
  ),
  GuideStep(
    icon: Icons.groups_rounded,
    title: 'Il tuo gruppo',
    description:
        'Qui trovi la lista dei ragazzi del tuo gruppo, con il riepilogo '
        'del gruppo e le informazioni principali.',
    demoRoute: '/my-group',
  ),
  GuideStep(
    icon: Icons.badge_rounded,
    title: 'Anagrafica ragazzi',
    description:
        'Cerca, filtra e modifica le schede dei ragazzi: contatti dei '
        'genitori, dati sanitari, allergie e consensi firmati.',
    demoRoute: '/students',
  ),
  GuideStep(
    icon: Icons.fact_check_rounded,
    title: 'Presenze',
    description:
        'Registra l\'appello di ogni incontro e consulta la griglia '
        'riepilogativa con tutti i presenti e gli assenti.',
    demoRoute: '/attendance-meetings',
  ),
  GuideStep(
    icon: Icons.calendar_month_rounded,
    title: 'Programmazione incontri',
    description:
        'Pianifica gli incontri del gruppo, distingui le giornate con '
        'i ragazzi dalle riunioni tra catechisti.',
    demoRoute: '/planning',
  ),
  GuideStep(
    icon: Icons.folder_copy_rounded,
    title: 'Documenti',
    description:
        'Gestisci il ciclo di vita dei documenti: autorizzazioni, moduli '
        'e consegne con il tracciamento per ogni ragazzo.',
    demoRoute: '/documents',
  ),
  GuideStep(
    icon: Icons.chat_rounded,
    title: 'Note di contatto',
    description:
        'Registra le comunicazioni con i genitori (di persona, WhatsApp '
        'o telefono) per avere sempre lo storico dei contatti.',
    demoRoute: '/contact-notes',
  ),
  GuideStep(
    icon: Icons.campaign_rounded,
    title: 'Avvisi per i genitori',
    description:
        'Crea avvisi e messaggi standard con i segnaposto automatici '
        '(nome del ragazzo, data dell\'incontro, assenze...).',
    demoRoute: '/avvisi',
  ),
  GuideStep(
    icon: Icons.menu_book_rounded,
    title: 'Contenuti catechetici',
    description:
        'Consulta e crea la tua libreria di catechesi: riferimenti '
        'biblici, tag e approfondimenti da associare agli incontri.',
    demoRoute: '/catechesi',
  ),
  GuideStep(
    icon: Icons.settings_rounded,
    title: 'Impostazioni',
    description:
        'Gestisci la sicurezza, le classi, il backup e l\'associazione '
        'di altri dispositivi per la sincronizzazione.',
    demoRoute: '/settings',
  ),
  GuideStep(
    icon: Icons.rocket_launch_rounded,
    title: 'Pronto per iniziare!',
    description:
        'I dati di esempio spariranno al prossimo riavvio, lasciando '
        'spazio ai tuoi dati reali. Buon lavoro!',
  ),
];

List<GuideStep> responsabileGuideSteps() => const [
  GuideStep(
    icon: Icons.waving_hand_rounded,
    title: 'Benvenuto, Responsabile',
    description:
        'Questa è una guida alle funzioni del Responsabile Catechistico.\n'
        'Per i primi passi trovi una parrocchia di esempio con classi, '
        'catechisti e ragazzi fittizi: verranno rimossi al riavvio.',
  ),
  GuideStep(
    icon: Icons.account_tree_rounded,
    title: 'Dashboard parrocchiale',
    description:
        'Vista ad albero della parrocchia: anno catechistico, percorsi, '
        'classi, catechisti e ragazzi, con le presenze aggregate.',
    demoRoute: '/parrocchia',
  ),
  GuideStep(
    icon: Icons.class_rounded,
    title: 'Classi e percorsi',
    description:
        'Crea e organizza le classi nei percorsi catechistici, assegna i '
        'catechisti e gestisci i livelli d\'anno.',
    demoRoute: '/parrocchia/classi',
  ),
  GuideStep(
    icon: Icons.people_alt_rounded,
    title: 'Catechisti',
    description:
        'Rubrica dei catechisti della parrocchia: anagrafica, telefono, '
        'classi assegnate e dispositivi collegati.',
    demoRoute: '/parrocchia/catechisti',
  ),
  GuideStep(
    icon: Icons.how_to_reg_rounded,
    title: 'Iscrizioni',
    description:
        'Censimento delle iscrizioni, gestione dei consensi e passaggio '
        'di anno catechistico.',
    demoRoute: '/parrocchia/iscrizioni',
  ),
  GuideStep(
    icon: Icons.meeting_room_rounded,
    title: 'Aule e orari',
    description:
        'Logistica parrocchiale: aule, capienze e slot settimanali delle '
        'classi, con controllo dei conflitti.',
    demoRoute: '/parrocchia/logistica',
  ),
  GuideStep(
    icon: Icons.notification_important_rounded,
    title: 'Allarmi assenze',
    description:
        'Monitora le assenze consecutive dei ragazzi oltre la soglia '
        'configurata, per intervenire tempestivamente.',
    demoRoute: '/parrocchia/allarmi',
  ),
  GuideStep(
    icon: Icons.approval_rounded,
    title: 'Consensi GDPR',
    description:
        'Gestisci la scheda di iscrizione firmata, i contributi volontari '
        'e il consenso al trattamento dei dati dei minori.',
    demoRoute: '/parrocchia/consensi',
  ),
  GuideStep(
    icon: Icons.hub_rounded,
    title: 'Rete catechistica',
    description:
        'Riunioni e avvisi globali della parrocchia, con il canale classe '
        'cifrato e il QR handshake di fiducia.',
    demoRoute: '/parrocchia/rete',
  ),
  GuideStep(
    icon: Icons.inventory_2_rounded,
    title: 'Archivio storico',
    description:
        'Snapshot immutabili di ogni anno concluso: promozioni, '
        'archiviazioni e progresso dei ragazzi nel tempo.',
    demoRoute: '/parrocchia/archivio',
  ),
  GuideStep(
    icon: Icons.receipt_long_rounded,
    title: 'Registro trattamenti',
    description:
        'Il Registro GDPR Art. 30: ogni operazione è tracciata e firmata '
        'contro manomissioni.',
    demoRoute: '/parrocchia/audit',
  ),
  GuideStep(
    icon: Icons.rocket_launch_rounded,
    title: 'Pronto per iniziare!',
    description:
        'I dati di esempio verranno rimossi al prossimo riavvio. '
        'Buon lavoro, Responsabile!',
  ),
];

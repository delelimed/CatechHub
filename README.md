<!-- markdownlint-disable MD033 -->
# CatechHub

![CatechHub](assets/images/logo_BG.png)

## Registro elettronico di catechismo — offline, sicuro, peer-to-peer

<p align="center">
  <img src="https://img.shields.io/github/v/release/delelimed/CatechHub?style=flat-square&label=versione&color=blue" alt="Versione"/>
  <a href="https://github.com/delelimed/CatechHub/actions/workflows/android-build.yml"><img src="https://github.com/delelimed/CatechHub/actions/workflows/android-build.yml/badge.svg" alt="Flutter Android Build"/></a>
  <img src="https://img.shields.io/github/downloads/delelimed/CatechHub/total?style=flat-square&label=downloads&color=success" alt="Download"/>
  <img src="https://img.shields.io/badge/licenza-MIT-green?style=flat-square" alt="Licenza"/>
  <img src="https://img.shields.io/badge/Android-API%2030%2B-brightgreen?style=flat-square&logo=android" alt="Android"/>
  <img src="https://img.shields.io/badge/flutter-3.12%2B-02569B?style=flat-square&logo=flutter" alt="Flutter"/>
  <img src="https://img.shields.io/badge/crittografia-AES--256--GCM-orange?style=flat-square" alt="Crittografia"/>
  <img src="https://img.shields.io/badge/sicurezza-hardware--backed-blue?style=flat-square" alt="HW Security"/>
  <img src="https://img.shields.io/badge/privacy-offline--first-purple?style=flat-square" alt="Privacy"/>
  <img src="https://img.shields.io/badge/GDPR-by--design-8A2BE2?style=flat-square" alt="GDPR"/>
  <img src="https://img.shields.io/badge/sincronizzazione-P2P%20BT%2FWiFi-0082FC?style=flat-square" alt="Sync"/>
</p>

---

CatechHub è un'applicazione mobile creata **da un catechista per i catechisti**. Digitalizza il registro parrocchiale in modo completo, sicuro e rispettoso della privacy dei minori. Tutti i dati restano sul tuo dispositivo, protetti da crittografia AES-256-GCM con chiave hardware-backed. Nessun cloud, nessun server centrale. L'app funziona completamente offline: la connessione serve **solo** per il controllo opzionale degli aggiornamenti (disattivabile) e per il feedback volontario all'autore.

## Perché CatechHub?

| Problema | Soluzione CatechHub |
| --- | --- |
| Fogli di carta persi o illeggibili | Anagrafica digitale con ricerca immediata |
| Dati sensibili di minori su cloud (o su fogli accessibili a tutti...) | **Zero dati su server esterni** — tutto rimane sul dispositivo |
| App che richiedono internet | **100% offline** — funziona anche in montagna o nelle sale più schermate |
| Condivisione complicata tra catechisti | **Sync P2P via Bluetooth/WiFi Direct** — crittografato end-to-end |
| Privacy sacrificata per la comodità | **Privacy by design** — biometria, schermo protetto, dati cifrati, GDPR by design |

## Sicurezza — Difesa a Strati

CatechHub adotta un approccio **defense-in-depth**, dove ogni livello è progettato per proteggere i dati anche se quello precedente venisse superato:

| Cosa protegge | Come lo fa |
| --- | --- |
| **Accesso all'app** | Solo con impronta digitale / riconoscimento facciale / PIN del telefono — nessuna password personalizzata, nessun account |
| **Blocco hardware** | Verifica TEE/StrongBox all'avvio — se hardware di sicurezza assente, l'app NON si avvia (nessun fallback software) |
| **Dati sul telefono** | Cifrati con **AES-256-GCM** — chiave master custodita in **AndroidKeyStore** (TEE/StrongBox hardware, nessun fallback software) |
| **Campi sensibili** | **Cifratura di campo** aggiuntiva (AES-256-GCM, chiave per-dispositivo) per i dati più delicati (allergie, note sanitarie, uscite autonome) |
| **Sincronizzazione P2P BT/WiFi** | End-to-end encryption con **TripleDH X25519 + HKDF-SHA256 + AES-256-GCM** — chiavi per-dispositivo per l'associazione, chiavi effimere per sessione (forward secrecy), **rotazione chiave di sessione ogni 30 minuti**, pairing code a 6 cifre anti-MitM, key pinning sulle riconnessioni, **doppio consenso** per dispositivi "Altro Catechista" |
| **Canale classe (P2P)** | **Chiave per-classe AES-256-GCM**: i dispositivi "Senza Titolo" ricevono solo blob opachi (relay) e non possono leggere i dati |
| **Canale parrocchiale (P2P)** | Avvisi e riunioni della rete parrocchiale scambiati **in chiaro** tra dispositivi associati: per scelta di design non contengono dati personali (solo testo di comunicazione). I dati personali passano sempre dal canale classe cifrato |
| **Condivisione QR** | Cifratura AES-256-GCM con **PIN a 12 cifre** (valido 3 minuti, PBKDF2-HMAC-SHA256 **350.000 iterazioni** per i nuovi pacchetti; 60.000 solo per compatibilità con i vecchi), checksum SHA-256 per chunk, chunking automatico, sync differenziale, **rate-limit anti-brute-force all'import** (5 tentativi errati → blocco 1 minuto) |
| **Schermo** | Blocco screenshot e screen recording non autorizzati con FLAG_SECURE |
| **Runtime** | freeRASP (Talsec) rileva e blocca root, emulatori, tampering, hooking e hacking |
| **Sessione** | Stato solo in RAM (mai persistito su disco); blocco automatico dopo 2 minuti in background e dopo 5 minuti di inattività in foreground |
| **Backup** | AES-256-GCM con derivazione **PBKDF2-HMAC-SHA256** — **210.000 iterazioni** e **PIN min. 12 caratteri alfanumerici** (chiave forte richiesta all'esportazione); l'**export conformità GDPR** (Registro Trattamenti) usa **350.000 iterazioni** con **anti-brute-force** (5 tentativi, blocco 30 min) |
| **Aggiornamenti** | Controllo versione verso GitHub con **certificate pinning SHA-256** (fail-closed), opzionale e disattivabile dalle impostazioni |
| **Associazioni P2P** | Chiavi X25519 per dispositivo salvate con l'associazione — chiave pubblica remota verificata ad ogni riconnessione (key pinning) |
| **Catena di fiducia** | Certificati di approvazione **Ed25519** (firma asimmetrica) con scadenza 30 giorni, verificati su una trust root pubblica (QR di fiducia), revoche firmate propagate peer-to-peer |
| **GDPR / Tracciabilità** | Ogni registrazione memorizza data, ora e autore dell'ultima modifica; **Registro Trattamenti** firmato **HMAC-SHA256** (audit log append-only) per ogni operazione rilevante |
| **Diritto all'oblio** | Tombstone **firmati** (HMAC-SHA256 sul canale P2P + firma **Ed25519 per-dispositivo**, asimmetrica e attribuibile) e propagati peer-to-peer che impediscono la "resurrezione" dei dati cancellati; hard delete irreversibile (solo Responsabile) |
| **Retention automatica** | Consensi con scadenza: scaduti → stato RITIRATO → 30 giorni di grazia → cancellazione a cascata automatica dei dati |

> **Nessun dato personale lascia mai il tuo telefono** se non durante una sincronizzazione volontaria con un altro catechista di tua fiducia, previa approvazione e crittografia end-to-end.

## Privacy e GDPR

CatechHub è progettata per **lasciare al catechista il pieno controllo dei propri dati**, in linea con il Regolamento Generale sulla Protezione dei Dati (GDPR — Reg. UE 2016/679):

- **L'app non condivide dati.** CatechHub non dispone di server né di servizi cloud, non invia dati a terzi e non integra sistemi di analytics, tracking o pubblicità. Nessuna informazione lascia il tuo dispositivo se non su tua esplicita iniziativa.
- **Sei tu a gestire i dati.** L'utente è il soggetto che tratta e gestisce i dati: inserimento, modifica ed eliminazione avvengono direttamente dal tuo dispositivo. Non esistono account remoti, profili online o registri lato server.
- **Dati sensibili trattati con cautela (art. 9 GDPR).** I dati dei minori sono informazioni "particolari" e come tali vengono trattati: cifrati con AES-256-GCM, custoditi nel secure storage hardware, con cifratura di campo aggiuntiva per i dati più delicati e accessibili solo previa autenticazione all'app.
- **Privacy by design e by default (art. 25 GDPR).** Minimo, essenziale: vengono raccolti solo i dati strettamente necessari, la crittografia è attiva di default e ogni funzione di condivisione richiede un consenso esplicito (doppio consenso per i catechisti, PIN per QR e backup).
- **Consensi con scadenza (art. 7, 9 GDPR).** In modalità Responsabile ogni iscritto ha un consenso privacy con **data di sottoscrizione e durata di validità** configurabile, registrato con **evidenza del firmatario** (nome del genitore/tutore) e l'**identità del catechista che ha registrato la firma** (voce immutabile nel Registro Trattamenti): l'app segnala i consensi in scadenza e applica automaticamente la retention (RITIRATO → grazia 30 giorni → cancellazione a cascata).
- **Sincronizzazione solo consensuale e verificata.** L'unico scambio possibile avviene peer-to-peer (Bluetooth/WiFi Direct) esclusivamente con dispositivi di tua fiducia, previo pairing verificato e crittografia end-to-end. Nessun intermediario. In modalità Responsabile solo i dispositivi **approvati** (certificati Ed25519) possono sincronizzare le classi.
- **Tracciabilità (art. 5.2 GDPR).** Registro Trattamenti **firmato HMAC-SHA256**: ogni operazione rilevante (iscrizione, modifica, consenso, passaggio anno, retention, oblio) è registrata con data, ora e autore. Il registro è append-only e verificabile.
- **Portabilità (art. 20 GDPR).** Puoi esportare l'intero database in un file `.catechhub` protetto da password e ripristinarlo su un altro dispositivo quando vuoi. È disponibile anche un **export conformità GDPR** (CSV del registro + pacchetto cifrato).
- **Diritto alla cancellazione (art. 17 GDPR).** Puoi eliminare definitivamente tutti i dati in qualsiasi momento dalle Impostazioni (cancellazione completa o selettiva). La cancellazione produce un **tombstone** che impedisce ai dati di riapparire tramite sincronizzazione. L'hard delete irreversibile (dati + tombstone dei dati) è riservato al Responsabile.
- **Mitigazione delle violazioni.** In caso di accesso fisico non autorizzato al dispositivo, i dati restano illeggibili grazie alla crittografia hardware-backed (AndroidKeyStore/TEE/StrongBox), al blocco biometrico e al blocco automatico della sessione.
- **Nessuna profilazione.** L'app non traccia i comportamenti, non costruisce profili e non invia alcuna statistica di utilizzo. Il feedback all'autore (Wiredash) è **opt-in** e disattivato per impostazione predefinita.

> CatechHub non è un servizio online: è uno strumento personale. I dati appartengono al catechista che li ha inseriti — e solo a lui. CatechHub **facilita** la conformità GDPR, non la sostituisce: la responsabilità del trattamento è del catechista/parrocchia.

## Cosa Puoi Fare

- **Anagrafica ragazzi** — Aggiungi, modifica, cerca e organizza gli iscritti in gruppi
- **Gestione multigruppo** — Crea, unisciti e gestisci più gruppi di catechismo; passa da un gruppo all'altro con un tap e copia i contenuti (anagrafica, presenze, programmazione) da un gruppo a un altro. Tutti i tuoi gruppi sono sempre accessibili da "I miei gruppi" nelle Impostazioni
- **Presenze** — Crea giornate, fai l'appello (con **conteggio rapido**), visualizza statistiche e griglie riepilogative, avvisi per assenze ripetute
- **Programmazione** — Pianifica incontri e associa materiale catechetico, con rilevamento dei conflitti e notifiche promemoria
- **Documenti** — Gestisci il ciclo di vita: crea, consegna, attendi riconsegna, archivia
- **Note contatti** — Tieni traccia delle comunicazioni con le famiglie
- **Condivisione QR** — Esporta e importa moduli selezionati in modo sicuro con PIN a 12 cifre temporaneo (3 minuti) e cifratura AES-256-GCM
- **Backup crittografato** — Salva e ripristina tutto il database con un file `.catechhub` protetto da password (AES-256-GCM + PBKDF2) e import con merge
- **Sync P2P Nearby** — Sincronizzazione continua in background via Bluetooth/WiFi Direct con crittografia end-to-end (TripleDH X25519 + HKDF-SHA256 + AES-256-GCM), rotazione chiavi di sessione ogni 30 minuti, pairing code a 6 cifre anti-MitM, key pinning per dispositivo, forward secrecy e sync differenziale. **Scope per classe**: decidi quali classi condividere con ciascun dispositivo. **Doppio consenso**: se entrambi i dispositivi sono "Altro Catechista", la sincronizzazione richiede l'autorizzazione esplicita di entrambi prima dello scambio dati.
- **Modalità Responsabile Catechistico** — Area dedicata al responsabile della parrocchia: dashboard parrocchiale con riepilogo (classi attive, ragazzi iscritti, catechisti), gestione delle classi raggruppate per **percorso** (attive/archiviate), iscrizioni con promozione e passaggio di anno automatico, **consensi privacy con durata di validità** e retention automatica, **Registro Trattamenti GDPR** (audit log firmato HMAC), gestione catechisti, **logistica delle aule** (slot settimanali, controllo conflitti, occupazione tabellare), **import ragazzi CSV/XLSX**, **allarme assenze** parrocchiale, rete parrocchiale e dispositivi fidati, **percorsi catechistici personalizzabili**, **Concludi anno catechistico**
- **Archivio Storico** — Chiusura dell'anno con **snapshot immutabili** del percorso di ogni ragazzo (classe, catechista, sacramenti, % presenze, valutazioni); consultazione per anno con accesso limitato (il catechista vede solo i propri ragazzi, il Responsabile tutto)
- **Supplenze** — In modalità "Associato", un catechista può delegare la propria classe a un collega con **delega crittografica via QR** (chiave temporanea AES-256 + ECDH + AES-256-GCM + HMAC), registro supplenze dedicato e revoca firmata
- **Logistica visibile anche agli associati** — Quando la modalità Responsabile è attiva, i dispositivi "Associato" possono consultare in **sola lettura** le aule, le stanze e la tabella orario settimanale. La modifica delle aule resta riservata al Responsabile
- **Catena di fiducia** — Nella modalità Responsabile ogni dispositivo collegato alla parrocchia deve essere **approvato** (certificato **Ed25519** con scadenza 30 giorni, trust root tramite QR di fiducia che trasporta solo la chiave pubblica) prima di poter sincronizzare le classi. Approvazioni e **revoche firmate** si gestiscono dal "Centro approvazioni" e si propagano peer-to-peer
- **Rete Catechistica Parrocchiale** — Canale di comunicazione tra i dispositivi approvati: **riunioni e avvisi parrocchiali** sincronizzati peer-to-peer (canale separato da quello delle classi, senza dati personali)
- **Comunicazioni automatiche** — Template WhatsApp con placeholders (nome ragazzo, assenze consecutive, data incontro, ecc.) e registrazione note di contatto
- **Tracciabilità modifiche** — Ogni record mostra data, ora e autore dell'ultima modifica, garantendo piena trasparenza su chi ha modificato cosa e quando
- **Esportazione report PDF** — Genera per la classe attualmente aperta un documento PDF A4 professionale con i moduli che preferisci: anagrafica, note di contatto, composizione del gruppo, presenze, statistiche, documenti, programmazione degli incontri e catechesi. Il PDF viene generato localmente e condiviso tramite il foglio nativo di Android senza mai passare da server intermedi
- **PDF e stampa** — Genera report presenze, statistiche assenze e liste gruppi
- **Allergie e uscite autonome** — Gestisci informazioni sensibili (con cifratura di campo aggiuntiva) con visibilità immediata
- **Notifiche incontri** — Promemoria locali prima degli incontri (contengono solo data e titolo, nessun dato personale)
- **Aggiornamenti** — Controllo versione da GitHub con certificate pinning, disattivabile dalle Impostazioni

## Tecnologie

| Area | Strumento |
| --- | --- |
| Framework | Flutter & Dart |
| Stato | Riverpod |
| Database locale | Hive (cifrato AES-256-GCM), auto-recovery per box |
| Chiave master | AndroidKeyStore (TEE/StrongBox hardware) — SecurityManager, nessun fallback software |
| Storage sicuro | flutter_secure_storage (Keystore hardware-backed) |
| Crittografia | cryptography (puro Dart): AES-256-GCM, X25519 (TripleDH/ECDH), Ed25519, PBKDF2-HMAC-SHA256 (350k per nuovi QR e export GDPR; 210k per i backup generali; 60k legacy QR), HKDF-SHA256, HMAC-SHA256 |
| Cifratura di campo | FieldEncryptionService — AES-256-GCM per i dati sensibili, chiave per-dispositivo |
| Sincronizzazione P2P | Google Nearby Connections (P2P_CLUSTER — Bluetooth/WiFi Direct) + protocollo a stati con sync differenziale, pairing code, key pinning, rotazione sessione |
| Canali di sincronizzazione | Canale classe cifrato per-classe + canale parrocchiale (riunioni/avvisi, non personali) |
| Condivisione QR | QR code con chunking, PIN 12 cifre (3 min, PBKDF2 350k per i nuovi pacchetti), checksum SHA-256, sync differenziale per modulo |
| Autenticazione | Biometria nativa Android (local_auth) — solo dispositivo |
| Comunicazioni | Template WhatsApp con placeholders, apertura via URL scheme |
| QR Code | mobile_scanner, qr_flutter |
| PDF | pdf, printing |
| Sicurezza runtime | freeRASP (Talsec) v8 |
| Aggiornamenti | GitHub API con certificate pinning SHA-256, notifiche locali |
| Sync status | Indicatore a pallino (verde/rosso/ciano/giallo) in app bar |
| Multigruppo | Cambio gruppo rapido (class switcher), "I miei gruppi", copia contenuti tra classi |

## Per Iniziare

1. **Scarica l'APK** dall'ultima [release su GitHub](https://github.com/delelimed/CatechHub/releases)
2. **Installa sul telefono Android** (versione 10.0 o superiore)
3. **Avvia e segui il setup guidato** — nome, cognome, gruppo
4. **Inizia a inserire i tuoi ragazzi** — il resto è intuitivo

Non serve registrazione, account, email o connessione internet. L'app richiede un dispositivo con **hardware di sicurezza** (TEE/StrongBox) e blocco schermo attivo.

## Stato del Progetto

- **Versione corrente:** [![GitHub Release](https://img.shields.io/github/v/release/delelimed/CatechHub?style=flat-square&label=v)](https://github.com/delelimed/CatechHub/releases/latest) [![GitHub Downloads](https://img.shields.io/github/downloads/delelimed/CatechHub/total?style=flat-square&label=downloads)](https://github.com/delelimed/CatechHub/releases/latest)
- **Piattaforma:** Android (minSdk 30)
- **Licenza:** MIT — libero da usare, modificare e distribuire

## Future Implementazioni

Vedi la [roadmap completa](FUTURE.md) per le funzionalità in sviluppo, pianificate e in valutazione.

## Documentazione

- [Documentazione utente](https://delelimed.github.io/CatechHub/)
- [Documentazione tecnica](https://delelimed.github.io/CatechHub/technical.html)
- [Informativa Privacy](https://delelimed.github.io/CatechHub/privacy.html)
- [Sezione GDPR e Sicurezza](https://delelimed.github.io/CatechHub/infos/index.html)
- [Sviluppatore](https://delelimed.github.io/CatechHub/developer.html)

## Licenza

```text
MIT License — Copyright (c) 2026 CatechHub

CatechHub è stato sviluppato interamente in "vibe coding" con l'ausilio dell'intelligenza artificiale, da un catechista (non da uno sviluppatore di professione). Il codice è aperto, verificabile e migliorabile da chiunque.

Fatto con dedizione da un catechista, per chi vive ogni giorno la bellezza di accompagnare bambini e ragazzi nel cammino di fede.
```
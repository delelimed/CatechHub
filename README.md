# CatechHub

![CatechHub](assets/images/logo.png)

## Registro elettronico di catechismo — offline, sicuro, peer-to-peer

<p align="center">
  <img src="https://img.shields.io/github/v/release/delelimed/CatechHub?style=flat-square&label=versione&color=blue" alt="Versione"/>
  <img src="https://img.shields.io/github/actions/workflow/status/delelimed/CatechHub/android-build.yml?style=flat-square&label=build&branch=debug" alt="Build"/>
  <img src="https://img.shields.io/github/downloads/delelimed/CatechHub/total?style=flat-square&label=downloads&color=success" alt="Download"/>
  <img src="https://img.shields.io/badge/licenza-MIT-green?style=flat-square" alt="Licenza"/>
  <img src="https://img.shields.io/badge/Android-API%2030%2B-brightgreen?style=flat-square&logo=android" alt="Android"/>
  <img src="https://img.shields.io/badge/flutter-3.12%2B-02569B?style=flat-square&logo=flutter" alt="Flutter"/>
  <img src="https://img.shields.io/badge/crittografia-AES--256--GCM-orange?style=flat-square" alt="Crittografia"/>
  <img src="https://img.shields.io/badge/privacy-offline--first-purple?style=flat-square" alt="Privacy"/>
  <img src="https://img.shields.io/badge/sincronizzazione-P2P%20Bluetooth-0082FC?style=flat-square" alt="Sync"/>
</p>

---

CatechHub è un'applicazione mobile creata **da un catechista per i catechisti**. Digitalizza il registro parrocchiale in modo completo, sicuro e rispettoso della privacy dei minori. Tutti i dati restano sul tuo dispositivo, protetti da crittografia AES-256-GCM. Nessun cloud, nessun server centrale, nessuna connessione internet necessaria.

## Perché CatechHub?

| Problema | Soluzione CatechHub |
| --- | --- |
| Fogli di carta persi o illeggibili | Anagrafica digitale con ricerca immediata |
| Dati sensibili di minori su cloud (o su fogli accessibili a tutti...) | **Zero dati su server esterni** — tutto rimane sul dispositivo |
| App che richiedono internet | **100% offline** — funziona anche in montagna o nelle sale più schermate |
| Condivisione complicata tra catechisti | **Sync P2P via Bluetooth** — crittografato end-to-end |
| Privacy sacrificata per la comodità | **Privacy by design** — biometria, schermo protetto, dati cifrati |

## Sicurezza — Difesa a Strati

CatechHub adotta un approccio **defense-in-depth**, dove ogni livello è progettato per proteggere i dati anche se quello precedente venisse superato:

| Cosa protegge | Come lo fa |
| --- | --- |
| **Accesso all'app** | Solo con impronta digitale / riconoscimento facciale / PIN del telefono — nessuna password personalizzata da ricordare |
| **Dati sul telefono** | Cifrati con **AES-256-GCM** — illeggibili anche se il file viene copiato |
| **Dati in sincronizzazione** | End-to-end encryption con scambio chiavi **ECDH P-256** via QR code |
| **Schermo** | Blocco screenshot e screen recording non autorizzati |
| **Runtime** | freeRASP rileva e blocca root, emulatori, tampering e hacking |
| **Sessione** | Blocco automatico dopo 2 minuti in background |
| **Backup** | Protetto da password con derivazione PBKDF2 (210.000 iterazioni) |

> **Nessun dato personale lascia mai il tuo telefono** se non durante una sincronizzazione volontaria con un altro catechista di tua fiducia.

## Cosa Puoi Fare

- **Anagrafica ragazzi** — Aggiungi, modifica, cerca e organizza gli iscritti in gruppi
- **Presenze** — Crea giornate, fai l'appello, visualizza statistiche
- **Programmazione** — Pianifica incontri e associa materiale catechetico
- **Documenti** — Gestisci il ciclo di vita: crea, consegna, attendi riconsegna, archivia
- **Note contatti** — Tieni traccia delle comunicazioni con le famiglie
- **Condivisione QR** — Esporta e importa moduli selezionati in modo sicuro
- **Backup crittografato** — Salva e ripristina tutto il database con un file `.catechub`
- **Sync P2P Bluetooth** — Sincronizza i dati con altri catechisti in modo sicuro e automatico
- **PDF e stampa** — Genera report presenze e liste gruppi
- **Allergie e uscite autonome** — Gestisci informazioni sensibili con visibilità immediata

## Tecnologie

| Area | Strumento |
| --- | --- |
| Framework | Flutter & Dart |
| Stato | Riverpod |
| Database locale | Hive (cifrato AES) |
| Crittografia | PointyCastle, cryptography (AES-256-GCM, PBKDF2, ECDH, HKDF) |
| Sincronizzazione | Bluetooth RFCOMM + protocollo CRDT |
| Autenticazione | Biometria nativa Android |
| QR Code | mobile_scanner, qr_flutter |
| PDF | pdf, printing |
| Sicurezza runtime | freeRASP (Talsec) |

## Per Iniziare

1. **Scarica l'APK** dall'ultima [release su GitHub](https://github.com/delelimed/CatechHub/releases)
2. **Installa sul telefono Android** (versione 10.0 o superiore)
3. **Avvia e segui il setup guidato** — nome, cognome, gruppo
4. **Inizia a inserire i tuoi ragazzi** — il resto è intuitivo

Non serve registrazione, account, email o connessione internet.

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
- [Sviluppatore](https://delelimed.github.io/CatechHub/developer.html)

## Licenza

```text
MIT License — Copyright (c) 2026 CatechHub

Fatto con dedizione da un catechista, per chi vive ogni giorno la bellezza di accompagnare bambini e ragazzi nel cammino di fede.
```

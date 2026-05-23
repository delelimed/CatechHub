# CatechHub

`CatechHub` è un'app Flutter per la gestione locale del registro di catechismo. È pensata per funzionare su dispositivi Android supportati, con archiviazione locale cifrata e autenticazione tramite PIN e biometria.

> Stato: **Alpha**
> 
> L'app è in fase iniziale di sviluppo. Alcune funzionalità possono cambiare e potrebbero esserci bug.

## Cosa fa

- Gestisce un registro di catechismo locale
- Permette l'accesso tramite PIN
- Supporta sblocco biometrico se il dispositivo lo consente
- Memorizza i dati localmente in modo sicuro con Hive
- Offre impostazioni utente con nome, cognome e nome del gruppo
- Non richiede connessione a internet per l'uso principale

## Come funziona

1. All'avvio, l'app controlla se è già stato configurato un PIN locale.
2. Se non è presente, viene richiesto di configurare:
   - Nome
   - Cognome
   - Gruppo
   - PIN
3. Dopo la configurazione iniziale, l'accesso successivo avviene con PIN o biometria.
4. I dati vengono salvati localmente e rimangono sul dispositivo.

## Principali funzionalità

- Autenticazione locale con PIN
- Supporto biometrico tramite `local_auth`
- Profilo utente con nome, cognome e gruppo
- Archiviazione cifrata locale con Hive e `flutter_secure_storage`
- Navigazione con `go_router`
- UI responsive e gestione dei dati offline

## Come compilare

### Prerequisiti

- Flutter SDK installato
- Dispositivo o emulatore Android/iOS configurato
- Ambiente di sviluppo funzionante su Windows, macOS o Linux

### Installazione

Apri il progetto nella cartella principale e esegui:

```powershell
cd c:\Users\eliad\Dev\CateREG_Locale
flutter pub get
```

### Esecuzione

Per eseguire l'app in modalità debug su un dispositivo collegato o emulatore:

```powershell
flutter run
```

Per compilare un APK Android:

```powershell
flutter build apk
```

Per generare eventuali file Hive con build runner (se necessari):

```powershell
flutter pub run build_runner build --delete-conflicting-outputs
```

## Struttura del progetto

- `lib/main.dart`: entry point dell'app
- `lib/core/auth/`: gestione autenticazione e provider
- `lib/core/storage/`: inizializzazione e accesso al database locale
- `lib/features/auth/`: login e onboarding
- `lib/features/settings/`: impostazioni utente
- `lib/features/classes/`: gestione dei gruppi

## Nota

L'app è in stato **Alpha** e le funzionalità potrebbero non essere definitive. Usa questa versione per test e sviluppo, non per ambiente di produzione.

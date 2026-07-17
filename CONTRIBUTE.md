# Contribuire a CatechHub

Grazie per il tuo interesse in CatechHub! Questo progetto è nato da un catechista per i catechisti, ed è aperto al contributo di chiunque voglia aiutare a migliorarlo.

## Come contribuire

### Segnalare bug o problemi

**Dall'app (consigliato):**
CatechHub ha una funzione di segnalazione integrata tramite Wiredash. Dalle impostazioni dell'app, tocca "Feedback e suggerimenti" e compila il modulo. La segnalazione include automaticamente la versione dell'app e le informazioni sul dispositivo.

**Su GitHub:**
In alternativa, apri una [issue su GitHub](https://github.com/delelimed/CatechHub/issues) descrivendo:
- Il problema (cosa ti aspettavi e cosa è successo)
- Versione dell'app (la trovi in Impostazioni → App)
- Dispositivo e versione Android
- Passi per riprodurre il problema

### Proporre nuove funzionalità

Puoi propormi idee tramite:
- **Telegram** (prossimamente) — canale ufficiale per discussioni e suggerimenti rapidi
- **Instagram** (prossimamente) — storie e sondaggi per votare le prossime funzionalità
- **GitHub** — apri una [issue](https://github.com/delelimed/CatechHub/issues) con descrizione, contesto ed eventuali mockup

### Contribuire con codice
1. Fai un fork del repository
2. Crea un branch per la tua modifica: `git checkout -b feature/mia-idea`
3. Fai le modifiche rispettando lo stile del codice esistente
4. Esegui `flutter analyze` per verificare che non ci siano errori
5. Fai commit e push, poi apri una Pull Request verso `develop`

## Linee guida

### Stile del codice
- Segui lo stile esistente: il codice originale usa `dart format` con le impostazioni predefinite
- Non aggiungere commenti al codice se non strettamente necessari
- Usa i type adapter di Hive con naming versionato (es. `students_box_v2`) per cambi di schema
- I provider Riverpod devono essere auto-dispose dove possibile

### Struttura del progetto
- `lib/features/` — ogni feature in una cartella separata con repository, provider e pagine
- `lib/core/` — servizi trasversali (auth, crittografia, storage, sicurezza)
- `lib/shared/` — modelli e widget condivisi

### Privacy e sicurezza
- Non introdurre mai dipendenze che inviano dati a server esterni
- Non rimuovere o indebolire i controlli di sicurezza (freeRASP, FLAG_SECURE, crittografia)
- I dati sensibili (allergie, minori) devono rimanere sempre cifrati sul dispositivo
- La box `catechesi_box` non deve mai essere inclusa nella sincronizzazione

## Build locale

### Prerequisiti
- Flutter SDK 3.12+ con Dart 3.12+
- Android Studio o toolchain Android SDK (minSdk 30, compileSdk 36, targetSdk 36)
- JDK 17+
- Kotlin 2.2.20

### Setup
```bash
git clone https://github.com/delelimed/CatechHub.git
cd CatechHub
flutter pub get

# Crea il file .env (vedi .env.example)
# freerasp richiede package name e signing cert hash
```

### Eseguire l'app
```bash
flutter run --dart-define-from-file=.env
```

### Build APK
```bash
flutter build apk --release --dart-define-from-file=.env --target-platform=android-arm64 --obfuscate --split-debug-info=./debug_info
```

## Ambiente di sviluppo

| Strumento | Versione |
|---|---|
| Flutter | 3.12+ |
| Dart | 3.12+ |
| Kotlin | 2.2.20 |
| Android Gradle Plugin | 8.11.1 |
| compileSdk | 36 |
| minSdk | 30 (Android 10+) |
| JVM target | 17 |

**Nota:** le versioni dei plugin nativi devono essere coerenti con quelle di Kotlin, AGP, e compileSdk dichiarate in `android/settings.gradle.kts`. Un mismatch causa crash istantaneo all'avvio (`ClassNotFoundException`) senza errori di compilazione.

## Licenza

Contribuendo, accetti che il tuo codice sia distribuito sotto licenza MIT come il resto del progetto.

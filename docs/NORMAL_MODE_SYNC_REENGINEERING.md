# Reingegnerizzazione Sync Modalità Normale — CatechHub

> **Non altera la modalità Responsabile.** Tutta la logica Responsabile (catena di fiducia, trust root Ed25519, approval chain) resta in `p2p_security_service.dart` e nei relativi test `trust_chain_test.dart`.

## Contratto utente tradotto in tecnica

| Richiesta | Implementazione |
|-----------|-----------------|
| **Mio Dispositivo → condividi anche `catechistId`** | `NormalModeSyncHandler.shareCatechistIdForMyDevice` + `P2PSyncService._maybeAdoptRemoteCatechistId` (delegato a handler quando `!isResponsabileMode`). Il `catechistId` viaggia SOLO in `p2p_identity` cifrato (AES-256-GCM con ECDH X25519). Se il dispositivo ricevente è fresco (nessuna classe legata al suo `catechistId`), lo adotta: entrambi convergono sulla stessa identità → `syncScope = null` (tutte le classi). |
| **Altro Catechista → associa alla classe + condividi dati** | `NormalModeSyncHandler.associateOtherCatechistToSharedClasses` + `P2PSyncService._updateClassAfterPairingNormal`. Atomico su Hive: `catechistIds`, `associatedCatechistIds`, `catechistRoles`, `catechistDeviceCounts`, `creatorCatechistId`. Solo le classi in `sharedClassIds` (scelte nel pairing) vengono toccate (minimizzazione). Subito dopo ` _performBidirectionalSync(endpointId)` cifrato. Entrambi i dispositivi ottengono copia locale completa della classe condivisa e possono lavorare offline; le modifiche sono CRDT LWW per-classe e riconvergono quando i dispositivi sono vicini. |
| **Realtime quando vicini via Nearby Share** | `Strategy.P2P_CLUSTER` (solo Bluetooth/WiFi Direct, mai internet) + discovery/advertising continuo (`_startAdvertising`/`_startDiscovery`) + `_watchLocalChanges` (watch Hive → debounce 500 ms → `_pushIncrementalSync` cifrato) + `_periodicSync` (60 s) + `_heartbeat` (30 s) + sync immediato post-associazione. Nessun dato perso anche se una modifica locale avviene durante una full-sync (incrementale parallelo). |
| **Altamente cifrato, standard militare, GDPR minori** | Vedi sezione sotto. |

## Stack crittografico (standard militare)

```
Scambio chiavi : X25519 ECDH (RFC 7748, 256-bit, ~128-bit security)
                 TripleDH: static↔static + static↔ephemeral×2 + ephemeral↔ephemeral
                 (forward secrecy: efimere per-sessione MAI persistite)
Derivazione    : HKDF-SHA256 (RFC 5869) con info
                 "CatechHub_P2P_Session_v3:<ids>:<windowId>" + nonce concordato
Cifratura      : AES-256-GCM (FIPS 140-2, NSA Suite B, nonce 96-bit, tag 128-bit,
                 AAD "CatechHub_Context_P2P_v1" / "CatechHub_ClassChannel_v1")
Rotazione      : finestra 30 min (sessionWindowIndex), keep corrente+precedente
Autenticazione : public-key pinning + SAS 6 cifre (pairing code) su
                 sharedSecret+nonce+efimere ordinate → MitM su efimera diverge
A riposo       : Hive AES-256 (chiave in Keystore/Keychain) + FieldEncryption
                 per PII (allergie, note, telefoni) con chiave per-dispositivo
```

Tutti i payload di sync (`p2p_sync_index`, `p2p_sync_data`, `p2p_identity`, ecc.) eccetto i 5 bootstrap (`p2p_handshake`, `ack`, …) sono **rifiutati se arrivano in chiaro** (`_plaintextAllowedTypes`).

## GDPR — dati particolari di minori (art. 9, art. 32, art. 25)

- **Cifratura in transito e a riposo** (art. 32.1.a) — vedi sopra + Hive + field encryption.
- **Pseudonimizzazione** — ovunque `catechistId` invece di nome; `local_catechist_id` mai esposto nel QR (solo nel canale cifrato).
- **Minimizzazione** (art. 5.1.c) — `HiveSyncEngine.buildLocalIndex(scopes)` e `applyRemoteRecords(scopes)` filtrano per `SyncClassScope`; per "Altro Catechista" solo classi condivise.
- **Limitazione conservazione** — associazioni P2P 30 gg (`isValid`), tombstones per hard-delete (FERPA/GDPR diritto oblio), demo-PII mai sincronizzata.
- **Privacy by design** — PII decifrata solo sull’egresso P2P già cifrato; il channel key per-classe impedisce relay in chiaro.
- **Resilienza** — box Hive aperti con recovery atomica; log redatti (M4) senza PII.

## File toccati

- `lib/features/sync/normal/normal_mode_sync_handler.dart` — **nuovo**, handler auditabile, NOP in responsabile.
- `lib/features/sync/p2p/p2p_sync_service.dart` — import handler, delega `_maybeAdopt…` e `_updateClassAfterPairing` per normale, sync iniziale cifrato post-associazione.
- `test/features/sync/normal/normal_mode_sync_handler_test.dart` — **nuovo**, 6 test per i due flussi + invariante responsabile + contratto crittografico.

## Verifica

```bash
dart analyze lib/features/sync/normal/normal_mode_sync_handler.dart  # 0 issue
dart analyze lib/features/sync/p2p/p2p_sync_service.dart              # 0 issue
flutter test test/features/sync/normal/normal_mode_sync_handler_test.dart # 6 passed
flutter test test/features/sync/p2p/                                  # 82 passed
```

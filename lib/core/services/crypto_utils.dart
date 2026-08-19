// ============================================================================
// Helper crittografici condivisi — byte-compatibili con `package:crypto` e
// `pointycastle`, basati esclusivamente su `package:cryptography` (puro Dart).
//
// Le varianti `*Sync` usano `toSync().hashSync`/`calculateMacSync` (implementazione
// pura Dart) per non propagare l'async ai chiamanti di SHA-256/HMAC.
// ============================================================================
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Converte i byte in esadecimale minuscolo, con lo stesso formato della
/// rappresentazione `toString()` di `package:crypto` (`Digest`/`Hmac`).
String bytesToHex(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// SHA-256 della stringa [data] come esadecimale minuscolo.
Future<String> sha256Hex(String data) async {
  final hash = await Sha256().hash(utf8.encode(data));
  return bytesToHex(hash.bytes);
}

/// SHA-256 dei byte [data] come esadecimale minuscolo.
Future<String> sha256HexBytes(List<int> data) async {
  final hash = await Sha256().hash(data);
  return bytesToHex(hash.bytes);
}

/// HMAC-SHA256 di [data] con chiave [key] come esadecimale minuscolo.
Future<String> hmacSha256Hex(List<int> key, List<int> data) async {
  final mac = await Hmac.sha256().calculateMac(
        data,
        secretKey: SecretKey(key),
      );
  return bytesToHex(mac.bytes);
}

/// HMAC-SHA256 di [data] con chiave [key] come byte grezzi.
Future<List<int>> hmacSha256Bytes(List<int> key, List<int> data) async {
  final mac = await Hmac.sha256().calculateMac(
        data,
        secretKey: SecretKey(key),
      );
  return mac.bytes;
}

/// SHA-256 sincrono della stringa [data] come esadecimale minuscolo.
String sha256HexSync(String data) {
  final hash = Sha256().toSync().hashSync(utf8.encode(data));
  return bytesToHex(hash.bytes);
}

/// SHA-256 sincrono dei byte [data] come byte grezzi.
List<int> sha256BytesSync(List<int> data) {
  final hash = Sha256().toSync().hashSync(data);
  return hash.bytes;
}

/// SHA-256 sincrono dei byte [data] come esadecimale minuscolo.
String sha256HexBytesSync(List<int> data) {
  final hash = Sha256().toSync().hashSync(data);
  return bytesToHex(hash.bytes);
}

/// HMAC-SHA256 sincrono di [data] con chiave [key] come esadecimale minuscolo.
String hmacSha256HexSync(List<int> key, List<int> data) {
  final mac = Hmac.sha256().toSync().calculateMacSync(
        data,
        secretKeyData: SecretKeyData(key),
        nonce: const [],
      );
  return bytesToHex(mac.bytes);
}

/// HMAC-SHA256 sincrono di [data] con chiave [key] come byte grezzi.
List<int> hmacSha256BytesSync(List<int> key, List<int> data) {
  final mac = Hmac.sha256().toSync().calculateMacSync(
        data,
        secretKeyData: SecretKeyData(key),
        nonce: const [],
      );
  return mac.bytes;
}
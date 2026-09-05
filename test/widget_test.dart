import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/main.dart';

void main() {
  setUp(() async {
    Hive.init(Directory.systemTemp.path);
    await Hive.openBox(
      LocalDatabase.authBox,
      bytes: Uint8List.fromList([]),
    );
  });

  tearDown(() async {
    await Hive.close();
  });

  testWidgets('CatechHub si avvia senza errori', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));

    // Pump limitati invece di pumpAndSettle: l'app programma inizializzazione
    // asincrona reale (permessi, provider) che nel FakeAsync di testWidgets
    // non termina mai, facendo scattare il timeout di pumpAndSettle.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
  });
}
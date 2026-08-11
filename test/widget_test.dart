import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/main.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('widget_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalDatabase.authBox);
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(LocalDatabase.authBox);
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('CatechHub si avvia senza errori', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

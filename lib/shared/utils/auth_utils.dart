import '../../../core/storage/local_database.dart';

String getCurrentCatechistName() {
  try {
    final auth = LocalDatabase.auth();
    return auth.get('local_user_name', defaultValue: '') as String;
  } catch (_) {
    return '';
  }
}

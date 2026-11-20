import 'dart:io';

import 'package:test/test.dart';

/// Guards the optional sync schema: it may hold nicknames and UI preferences,
/// and nothing that could identify or unlock a TV.
void main() {
  final file = File('../../supabase/migrations/0001_preferences.sql');
  final schema = file.readAsStringSync();

  test('both tables enable row level security', () {
    final enabled = RegExp(
      r'alter table public\.\w+ enable row level security',
      caseSensitive: false,
    ).allMatches(schema);
    expect(enabled.length, 2);
  });

  test('every policy is scoped to auth.uid()', () {
    final checks = RegExp(r'auth\.uid\(\) = user_id').allMatches(schema);
    expect(
      checks.length,
      greaterThanOrEqualTo(4),
      reason: 'each table needs USING and WITH CHECK on the owner column',
    );
  });

  test('no column can hold a secret, key, address or network identifier', () {
    final forbidden = RegExp(
      r'\b(client_?key|key|secret|token|password|mac|host|hostname|ip|ip_address|address|ssid|bssid)\b',
      caseSensitive: false,
    );
    final columns = RegExp(
      r'^\s{2}(\w+)\s',
      multiLine: true,
    ).allMatches(schema).map((RegExpMatch match) => match.group(1)!).toSet();

    expect(columns, isNotEmpty);
    for (final column in columns) {
      expect(
        forbidden.hasMatch(column),
        isFalse,
        reason: 'column "$column" looks like it could store something private',
      );
    }
  });

  test('signed-out roles are revoked', () {
    expect(schema, contains('from anon'));
  });
}

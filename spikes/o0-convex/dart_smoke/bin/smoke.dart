import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Headless proof of the Convex **HTTP-action** transport from Dart.
///
/// This exercises the plain-HTTP path (Convex serves httpActions on the
/// `.convex.site` domain, NOT `.convex.cloud`). It does NOT test the
/// convex_flutter WebSocket/sync client or auth — that lives in the Flutter
/// throwaway target (needs a Flutter runtime).
///
/// Usage:
///   dart run bin/smoke.dart https://<deployment>.convex.site
/// or set CONVEX_SITE_URL. If given a `.convex.cloud` URL, we rewrite the host
/// to `.convex.site` (the HTTP-actions domain).
Future<void> main(List<String> args) async {
  final raw = (args.isNotEmpty ? args.first : Platform.environment['CONVEX_SITE_URL'] ?? '')
      .trim();
  if (raw.isEmpty) {
    stderr.writeln('Pass the deployment URL (…convex.site or …convex.cloud) as arg 1 '
        'or set CONVEX_SITE_URL.');
    exitCode = 2;
    return;
  }
  final base = raw.replaceFirst('.convex.cloud', '.convex.site').replaceAll(RegExp(r'/+$'), '');

  var passed = 0, failed = 0;
  void check(String name, bool ok, [String detail = '']) {
    stdout.writeln('${ok ? '✅' : '❌'} $name${detail.isEmpty ? '' : ' — $detail'}');
    ok ? passed++ : failed++;
  }

  // 1) GET /ping
  try {
    final r = await http.get(Uri.parse('$base/ping'));
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    check('GET /ping', r.statusCode == 200 && body['ok'] == true, 'status ${r.statusCode}');
  } catch (e) {
    check('GET /ping', false, '$e');
  }

  // 2) POST /echo
  try {
    final r = await http.post(
      Uri.parse('$base/echo'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'message': 'hello from dart'}),
    );
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    check('POST /echo', r.statusCode == 200 && body['echoed'] == 'hello from dart',
        'status ${r.statusCode}, len=${body['len']}');
  } catch (e) {
    check('POST /echo', false, '$e');
  }

  stdout.writeln('\n$passed passed, $failed failed  (base: $base)');
  exitCode = failed == 0 ? 0 : 1;
}

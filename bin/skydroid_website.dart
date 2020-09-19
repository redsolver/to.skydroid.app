import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:markdown/markdown.dart';
import 'package:mustache_template/mustache_template.dart';
import 'package:yaml/yaml.dart';
import 'package:http/http.dart' as http;

Template template;

Future main() async {
  template = Template(File('html/index.html').readAsStringSync(encoding: utf8),
      name: 'index.html');

  var server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    4040,
  );
  print('Listening on localhost:${server.port}');

  server.listen((req) async {
    try {
      await handleRequest(req);
    } catch (e, st) {
      print(e);
      print(st);
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (e) {}
    }
  });
  Stream.periodic(Duration(minutes: 30)).listen((event) {
    dnsCache = {};
  });
}

Map<String, String> dnsCache = {};

Future handleRequest(HttpRequest req) async {
  if (req.uri.path.startsWith('/assets')) {
    if (req.uri.path == '/assets/app.css') {
      req.response.headers.add('content-type', 'text/css');
      req.response.add(File('html/assets/app.css').readAsBytesSync());
      await req.response.close();
    } else if (req.uri.path == '/assets/app.bundle.js') {
      req.response.headers.add('content-type', 'text/javascript');
      req.response.add(File('html/assets/app.bundle.js').readAsBytesSync());
      await req.response.close();
    } else if (req.uri.path == '/assets/skydroid.svg') {
      req.response.headers.add('content-type', 'image/svg+xml');
      req.response.add(File('html/assets/skydroid.svg').readAsBytesSync());
      await req.response.close();
    } else {
      req.response.statusCode = 404;
      await req.response.close();
    }
    return;
  }
  if (req.uri.path == '/favicon.ico') {
    req.response.headers.add('content-type', 'image/x-icon');
    req.response.add(File('html/favicon.ico').readAsBytesSync());
    await req.response.close();
    return;
  } else if (req.uri.path == '/.well-known/assetlinks.json') {
    req.response.headers.add('content-type', 'application/json');
    req.response
        .add(File('html/.well-known/assetlinks.json').readAsBytesSync());
    await req.response.close();
    return;
  }

  if (req.uri.pathSegments.isEmpty) {
    req.response.statusCode = 404;

    await req.response.close();
    return;
  }
  print('${req.uri.path}');

  final name = req.uri.pathSegments.first;
  String nameRes;

  print(name);

  if (dnsCache.containsKey(name)) {
    nameRes = dnsCache[name];
  } else {
    final res = await http.post('https://dns.skydroid.app/multi-dns-query',
        body: json.encode({
          "type": 16,
          "names": [name]
        }));

    nameRes = (json.decode(res.body)['names'][name] as List)
        .cast<String>()
        .firstWhere((String n) => n.startsWith('skydroid-app='));

    if ((nameRes ?? '').isNotEmpty) {
      dnsCache[name] = nameRes;
    }
  }

  final parts = nameRes.split('+');

  final yamlFile = File('data/${parts[2]}.yaml');

  if (!yamlFile.existsSync()) {
    final metaRes = await http.get(resolveUrl('sia://${parts[1]}'));

    final hash = sha256.convert(metaRes.bodyBytes);

    if (hash.toString() != parts[2]) {
      throw Exception('Invalid hash');
    }

    yamlFile.writeAsBytesSync(metaRes.bodyBytes);
  }

  req.response.headers.add('content-type', 'text/html');

  final data = loadYaml(yamlFile.readAsStringSync());

  final localized = data['localized']['en-US'];

  List screenshots = [];

  try {
    final screenshotsBaseUrl = localized['phoneScreenshotsBaseUrl'] ?? '';

    for (String s in localized['phoneScreenshots']) {
      screenshots.add({
        'src': resolveUrl(screenshotsBaseUrl + s),
      });
    }
  } catch (e) {
    screenshots = [];
  }

  final rendered = template.renderString({
    'screenshots': screenshots,
    'icon': resolveUrl(data['icon']),
    'summary': localized['summary'],
    'name': data['name'],
    'author': data['author'],
    'description':
        markdownToHtml(data['description'] ?? localized['description'] ?? ''),
    'showScreenshots': screenshots.isNotEmpty,
  });
  //print(rendered);

  req.response.add(utf8.encode(rendered));
  await req.response.close();
}

String resolveUrl(String url) {
  if (url.startsWith('sia://')) {
    return 'https://siasky.net/${url.substring(6)}';
  } else {
    return url;
  }
}

import 'dart:convert';

import 'package:string_validator/string_validator.dart';
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

import 'parser/base.dart';
import 'parser/html_parser.dart';
import 'parser/json_ld_parser.dart';
import 'parser/og_parser.dart';
import 'parser/twitter_parser.dart';
import 'parser/util.dart';

class LinkAnalyzer {
  static final Map<String?, Metadata> _map = {};

  /// Is it an empty string
  static bool isNotEmpty(String? str) {
    return str != null && str.isNotEmpty && str.trim().length > 0;
  }

  /// return [Metadata] from cache if app is not killed
  static Metadata? getInfoFromCache(String? url) {
    final Metadata? info = _map[url];
    if (info != null) {
      if (!info.timeout.isAfter(DateTime.now())) {
        _map.remove(url);
      }
    }
    return info;
  }

  /// Fetches a [url], validates it, and returns [Metadata].
  static Future<Metadata?> getInfo(String url,
      {Duration cache = const Duration(hours: 24)}) async {
    Metadata? info = getInfoFromCache(url);
    if (info != null) return info;

    // info = await _getInfo(url, multimedia);
    if (!isURL(url)) return null;

    /// Default values; Domain name as the [title],
    /// URL as the [description]
    info?.title = getDomain(url);
    info?.desc = url;
    info?.url = url;

    // Make our network call
    final response = await http.get(Uri.parse(url));
    final headerContentType = response.headers['content-type'];

    if (headerContentType != null && headerContentType.startsWith(r'image/')) {
      info?.title = '';
      info?.desc = '';
      info?.image = url;
      return info;
    }

    final document = responseToDocument(response);
    if (document == null) return info;

    final _data = _extractMetadata(document, url: url);

    if (_data == null)
      return info;
    else {
      _data.timeout = DateTime.now().add(cache);
      _map[url] = _data;
    }

    return _data;
  }

  /// Takes an [http.Response] and returns a [html.Document]
  static Document? responseToDocument(http.Response response) {
    if (response.statusCode != 200) return null;

    Document? document;
    try {
      document = parser.parse(utf8.decode(response.bodyBytes));
    } catch (err) {
      return document;
    }

    return document;
  }

  /// Returns instance of [Metadata] with data extracted from the [html.Document]
  /// Provide a given url as a fallback when there are no Document url extracted
  /// by the parsers.
  ///
  /// Future: Can pass in a strategy i.e: to retrieve only OpenGraph, or OpenGraph and Json+LD only
  static Metadata? _extractMetadata(Document document, {String? url}) {
    return _parse(document, url: url);
  }

  /// This is the default strategy for building our [Metadata]
  ///
  /// It tries [OpenGraphParser], then [TwitterParser],
  /// then [JsonLdParser], and falls back to [HTMLMetaParser] tags for missing data.
  /// You may optionally provide a URL to the function,
  /// used to resolve relative images or to compensate for the
  /// lack of URI identifiers from the metadata parsers.
  static Metadata _parse(Document? document, {String? url}) {
    final output = Metadata();

    final parsers = [
      _openGraph(document),
      _twitterCard(document),
      _jsonLdSchema(document),
      _htmlMeta(document),
    ];

    for (final p in parsers) {
      output.title ??= p.title;
      output.desc ??= p.desc;
      output.image ??= p.image;
      output.url ??= p.url;

      if (output.hasAllMetadata) break;
    }
    // If the parsers did not extract a URL from the metadata, use the given
    // url, if available. This is used to attempt to resolve relative images.
    final _url = output.url ?? url;
    final image = output.image;
    if (_url != null && image != null) {
      output.image = Uri.parse(_url).resolve(image).toString();
    }

    return output;
  }

  static Metadata _openGraph(Document? document) {
    return OpenGraphParser(document).parse();
  }

  static Metadata _htmlMeta(Document? document) {
    return HtmlMetaParser(document).parse();
  }

  static Metadata _jsonLdSchema(Document? document) {
    return JsonLdParser(document).parse();
  }

  static Metadata _twitterCard(Document? document) {
    return TwitterParser(document).parse();
  }
}

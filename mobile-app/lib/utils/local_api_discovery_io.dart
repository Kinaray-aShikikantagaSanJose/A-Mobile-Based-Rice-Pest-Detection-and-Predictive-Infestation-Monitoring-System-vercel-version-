/// Native local-network discovery for Android, iOS and desktop.
///
/// This file is selected only when dart:io is available. The browser build
/// selects local_api_discovery_stub.dart instead.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const int _backendPort = 8000;
const int _discoveryPort = int.fromEnvironment(
  'DISCOVERY_PORT',
  defaultValue: 8001,
);
const String _discoveryRequest = 'PALAY_PATROL_DISCOVER_V1';
const Duration _broadcastWait = Duration(milliseconds: 2500);
const Duration _connectTimeout = Duration(milliseconds: 600);

const List<String> _skipInterfaces = [
  'rmnet',
  'ccmni',
  'pdp',
  'tun',
  'dummy',
];

/// Finds the API on a shared Wi-Fi, Ethernet, hotspot or tethered network.
///
/// A candidate is accepted only after [isBackend] confirms its /openapi.json
/// title. HTTPS is preferred; HTTP is allowed only when [requireHttps] is false.
Future<String?> discoverLocalApi({
  required Future<bool> Function(String base) isBackend,
  required bool requireHttps,
}) async {
  final prefixes = await _localPrefixes();
  return await _broadcastDiscover(
        prefixes,
        isBackend: isBackend,
        requireHttps: requireHttps,
      ) ??
      await _scanSubnets(
        prefixes,
        isBackend: isBackend,
        requireHttps: requireHttps,
      );
}

/// First three octets of each usable IPv4 address on this phone.
Future<Set<String>> _localPrefixes() async {
  final prefixes = <String>{};
  for (final iface in await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  )) {
    if (_skipInterfaces.any(iface.name.toLowerCase().contains)) continue;
    for (final address in iface.addresses) {
      if (address.isLoopback || address.isLinkLocal) continue;
      final parts = address.address.split('.');
      prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
    }
  }
  return prefixes;
}

/// Asks every network the phone is on where the Palay Patrol server is.
Future<String?> _broadcastDiscover(
  Set<String> prefixes, {
  required Future<bool> Function(String base) isBackend,
  required bool requireHttps,
}) async {
  RawDatagramSocket? socket;
  final result = Completer<String?>();
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final targets = <InternetAddress>{
      InternetAddress('255.255.255.255'),
      for (final prefix in prefixes) ...[
        InternetAddress('$prefix.255'),
        InternetAddress(
          '${prefix.substring(0, prefix.lastIndexOf('.'))}.255.255',
        ),
      ],
    };
    final checked = <String>{};
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket?.receive();
      if (datagram == null) return;
      final url = _parseReply(datagram);
      if (url == null || !checked.add(url)) return;
      _confirm(
        url,
        isBackend: isBackend,
        requireHttps: requireHttps,
      ).then((accepted) {
        if (accepted != null && !result.isCompleted) result.complete(accepted);
      });
    });

    final request = utf8.encode(_discoveryRequest);
    for (final delay in const [0, 400, 1000]) {
      if (result.isCompleted) break;
      await Future<void>.delayed(Duration(milliseconds: delay));
      for (final target in targets) {
        try {
          socket.send(request, target, _discoveryPort);
        } catch (_) {
          // No route to that network right now.
        }
      }
    }
    return await result.future.timeout(
      _broadcastWait,
      onTimeout: () => null,
    );
  } catch (_) {
    return null;
  } finally {
    socket?.close();
  }
}

String? _parseReply(Datagram datagram) {
  try {
    final data = jsonDecode(utf8.decode(datagram.data));
    if (data is! Map || data['service'] != 'palay-patrol') return null;
    final port = (data['port'] as num?)?.toInt() ?? _backendPort;
    final scheme = data['scheme'] == 'http' ? 'http' : 'https';
    return '$scheme://${datagram.address.address}:$port';
  } catch (_) {
    return null;
  }
}

/// HTTPS first; plain HTTP is considered only when [requireHttps] is false.
Future<String?> _confirm(
  String url, {
  required Future<bool> Function(String base) isBackend,
  required bool requireHttps,
}) async {
  final uri = Uri.parse(url);
  final secure = uri.replace(scheme: 'https').toString();
  if (await isBackend(secure)) return secure;
  if (requireHttps) return null;
  final plain = uri.replace(scheme: 'http').toString();
  return await isBackend(plain) ? plain : null;
}

Future<String?> _scanSubnets(
  Set<String> prefixes, {
  required Future<bool> Function(String base) isBackend,
  required bool requireHttps,
}) async {
  final hosts = <String>{'10.0.2.2', '127.0.0.1'};
  for (final prefix in prefixes) {
    for (var i = 1; i < 255; i++) {
      hosts.add('$prefix.$i');
    }
  }

  final result = Completer<String?>();
  var pending = hosts.length;
  for (final host in hosts) {
    _probeHost(
      host,
      isBackend: isBackend,
      requireHttps: requireHttps,
    ).then((url) {
      if (url != null && !result.isCompleted) result.complete(url);
      if (--pending == 0 && !result.isCompleted) result.complete(null);
    });
  }
  return result.future;
}

/// Fast TCP check first, then verify the candidate is our FastAPI server.
Future<String?> _probeHost(
  String host, {
  required Future<bool> Function(String base) isBackend,
  required bool requireHttps,
}) async {
  try {
    final socket = await Socket.connect(
      host,
      _backendPort,
      timeout: _connectTimeout,
    );
    socket.destroy();
  } catch (_) {
    return null;
  }
  return _confirm(
    'https://$host:$_backendPort',
    isBackend: isBackend,
    requireHttps: requireHttps,
  );
}

/// Browser-safe fallback for local API discovery.
///
/// Browsers cannot inspect local network interfaces or open UDP/TCP sockets.
/// Deployed web builds use the fixed HTTPS API_URL instead.
Future<String?> discoverLocalApi({
  required Future<bool> Function(String base) isBackend,
  required bool requireHttps,
}) async {
  return null;
}

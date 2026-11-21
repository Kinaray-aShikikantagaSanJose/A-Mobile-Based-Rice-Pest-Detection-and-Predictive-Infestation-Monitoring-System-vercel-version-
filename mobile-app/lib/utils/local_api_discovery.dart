/// Selects native LAN discovery on VM platforms and a no-socket fallback
/// in browsers. The implementations expose the same discoverLocalApi API.
export 'local_api_discovery_stub.dart'
    if (dart.library.io) 'local_api_discovery_io.dart';

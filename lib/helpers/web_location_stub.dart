import '../services/location_service.dart';

/// Stub untuk platform non-web.
/// Di web, digantikan oleh [web_location_impl.dart].
Future<LocationResult?> getWebLocation() async => null;

/// Conditional export: uses dart:html on web, stub on other platforms.
export 'web_camera_stub.dart' if (dart.library.html) 'web_camera_impl.dart';

// Conditional export: gunakan implementasi dart:html di web,
// stub kosong di platform lain.
export 'web_camera_capture_stub.dart'
    if (dart.library.html) 'web_camera_capture_impl.dart';

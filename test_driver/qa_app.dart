// Entrypoint for driving the app under QA with the Flutter driver extension
// enabled, so the Dart MCP tooling can tap, read and screenshot the running
// app. Not part of the shipped app. Launch with:
//
//   flutter run -t test_driver/qa_app.dart -d <device>
import 'package:flutter_driver/driver_extension.dart';
import 'package:swithfiber_tech_ps/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main();
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/sync/background_sync_service.dart';

String _stripComments(String source) {
  final withoutBlock = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return withoutBlock.replaceAll(RegExp(r'//.*'), '');
}

void main() {
  group('iOS BGTaskScheduler TestFlight launch safety', () {
    test(
      'Info.plist declares permitted background task identifier and modes',
      () {
        final plist = File('ios/Runner/Info.plist').readAsStringSync();

        final permittedMatch = RegExp(
          r'<key>BGTaskSchedulerPermittedIdentifiers</key>\s*<array>([\s\S]*?)</array>',
        ).firstMatch(plist);
        expect(permittedMatch, isNotNull);
        expect(
          permittedMatch!.group(1),
          contains('<string>$switchfiberBackgroundSyncTask</string>'),
        );

        final modesMatch = RegExp(
          r'<key>UIBackgroundModes</key>\s*<array>([\s\S]*?)</array>',
        ).firstMatch(plist);
        expect(modesMatch, isNotNull);
        expect(modesMatch!.group(1), contains('<string>fetch</string>'));
        expect(modesMatch.group(1), contains('<string>processing</string>'));
      },
    );

    test(
      'AppDelegate pre-registers periodic BGTask and plugin registrant before didFinishLaunching returns',
      () {
        final raw = File('ios/Runner/AppDelegate.swift').readAsStringSync();
        final active = _stripComments(raw);

        final methodStart = active.indexOf('didFinishLaunchingWithOptions');
        final returnSuper = active.indexOf(
          'return super.application(application, didFinishLaunchingWithOptions: launchOptions)',
        );
        expect(methodStart, greaterThanOrEqualTo(0));
        expect(returnSuper, greaterThan(methodStart));

        final bodyBeforeReturn = active.substring(methodStart, returnSuper);
        expect(
          bodyBeforeReturn,
          contains('WorkmanagerPlugin.registerPeriodicTask('),
        );
        expect(
          bodyBeforeReturn,
          contains('withIdentifier: "$switchfiberBackgroundSyncTask"'),
        );
        expect(
          bodyBeforeReturn,
          contains('earliestBeginInSeconds: NSNumber(value:'),
        );
        expect(
          bodyBeforeReturn,
          contains('WorkmanagerPlugin.setPluginRegistrantCallback'),
        );
        expect(
          bodyBeforeReturn,
          contains('GeneratedPluginRegistrant.register(with: registry)'),
        );
      },
    );

    test(
      'BackgroundSyncService sets explicit initialDelay on registerPeriodicTask',
      () {
        final raw = File('lib/core/sync/background_sync_service.dart')
            .readAsStringSync();
        final active = _stripComments(raw);

        final registerMatch = RegExp(
          r'Workmanager\(\)\.registerPeriodicTask\(([\s\S]*?)\);',
        ).firstMatch(active);
        expect(registerMatch, isNotNull);
        expect(registerMatch!.group(1), contains('initialDelay:'));
      },
    );
  });
}

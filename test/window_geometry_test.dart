import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_present/main.dart';

void main() {
  const channel = MethodChannel('simple_present/window');
  const codec = StandardMethodCodec();

  for (final closeWindow in [false, true]) {
    testWidgets(
      closeWindow
          ? 'native close persists task window geometry before exiting'
          : 'task window restores geometry and persists configure events',
      (tester) async {
        await tester.runAsync(() async {
          final directory =
              await Directory.systemTemp.createTemp('window-test-');
          final appDirectory =
              Directory('${directory.path}/simplepresent-debug');
          await appDirectory.create();
          final file = File(
            '${appDirectory.path}/simplepresent_task_window_geometry.json',
          );
          final saved = <String, dynamic>{
            'x': -120,
            'y': 90,
            'width': 820,
            'height': 640,
            'maximized': false,
          };
          await file.writeAsString(jsonEncode(saved));
          final current = {...saved, 'x': 220, 'width': 940};
          final trackingEnabled = Completer<void>();
          Map<dynamic, dynamic>? restored;
          var closed = false;
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          for (final name in const [
            'xyz.luan/audioplayers.global',
            'xyz.luan/audioplayers.global/events',
          ]) {
            messenger.setMockMethodCallHandler(
              MethodChannel(name),
              (_) async => null,
            );
          }
          messenger.setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers'),
            (call) async {
              if (call.method == 'create') {
                final playerId = (call.arguments as Map)['playerId'];
                messenger.setMockMethodCallHandler(
                  MethodChannel('xyz.luan/audioplayers/events/$playerId'),
                  (_) async => null,
                );
              }
              return null;
            },
          );
          messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.path,
          );
          messenger.setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'setWindowGeometry':
                restored = call.arguments as Map;
                return true;
              case 'enableWindowGeometryTracking':
                trackingEnabled.complete();
                return true;
              case 'getWindowGeometry':
                return current;
              case 'closeWindow':
                expect(jsonDecode(await file.readAsString()), current);
                closed = true;
                return true;
              default:
                return null;
            }
          });
          try {
            await tester.pumpWidget(const MaterialApp(
              home: TaskWindowPage(taskId: 'missing', closeAppOnExit: true),
            ));
            await trackingEnabled.future.timeout(const Duration(seconds: 10));
            await tester.pump();
            expect(restored, saved);
            final completed = Completer<void>();
            messenger.handlePlatformMessage(
              channel.name,
              codec.encodeMethodCall(MethodCall(
                closeWindow ? 'closeRequested' : 'windowGeometryChanged',
              )),
              (_) => completed.complete(),
            );
            await completed.future.timeout(const Duration(seconds: 10));
            expect(jsonDecode(await file.readAsString()), current);
            expect(closed, closeWindow);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            messenger.setMockMethodCallHandler(channel, null);
            messenger.setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
          }
        });
      },
    );
  }
}

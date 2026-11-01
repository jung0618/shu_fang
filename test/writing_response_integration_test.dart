import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/direct_llm_client.dart';
import 'package:shufang_flutter/services/writing_assistant.dart';
import 'package:shufang_flutter/services/writing_request_ledger.dart';
import 'package:shufang_flutter/services/writing_response_store.dart';
import 'package:shufang_flutter/store/local_data_source.dart';

import 'writing_request_ledger_test.dart' show requestPlan;

void main() {
  late Directory root;
  const body = '窗外的雨停了。\n她仍握着那只杯子。🌧';
  const content = DirectLlmEvent(
    type: DirectLlmEventType.content,
    content: body,
  );
  const done = DirectLlmEvent(type: DirectLlmEventType.done);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('shufang-response-stream-');
    localDataSource.selectWorkspace(root.path, isPrimary: false);
  });
  tearDown(() async {
    localDataSource.clearUser();
    await root.delete(recursive: true);
  });
  Future<WritingRequestRecord> record() async =>
      (await WritingRequestLedger.read(root.path)).records.single;

  test(
    'done and completion callback follow durable recoverable body',
    () async {
      var calls = 0;
      var completions = 0;
      await for (final event in WritingAssistant.stream(
        plan: requestPlan(),
        model: 'synthetic-only',
        useEngine: true,
        transportOverride: (receipt) async* {
          calls++;
          receipt({'api_key': 'synthetic-secret-do-not-store'});
          yield content;
          yield done;
        },
        onCompleted: (_) => completions++,
      )) {
        if (event.type == DirectLlmEventType.done) {
          final saved = await record();
          final restored = await WritingResponseStore.readCompleted(
            root: root.path,
            record: saved,
          );
          expect(saved.state, 'completed');
          expect(completions, 1);
          expect(restored.availability, WritingResponseAvailability.available);
          expect(restored.body, body);
          expect(restored.canCopy, isTrue);
          expect(saved.result['settlement'], 'unknown');
          expect(saved.result['cost'], isNull);
          final raw =
              await File(
                '${root.path}/.shufang/responses/${saved.id}.json',
              ).readAsString();
          expect(raw, isNot(contains('synthetic-secret-do-not-store')));
          expect(raw, isNot(contains('他没有开口')));
        }
      }
      expect(calls, 1);
    },
  );

  test('missing done never creates complete candidate or retries', () async {
    var calls = 0;
    await expectLater(
      WritingAssistant.stream(
        plan: requestPlan(),
        model: 'synthetic-only',
        useEngine: true,
        transportOverride: (_) async* {
          calls++;
          yield content;
        },
      ).toList(),
      throwsStateError,
    );
    final saved = await record();
    final restored = await WritingResponseStore.readCompleted(
      root: root.path,
      record: saved,
    );
    expect(saved.state, 'failed');
    expect(restored.canCopy, isFalse);
    expect(restored.body, isNull);
    expect(calls, 1);
    expect(
      await File('${root.path}/.shufang/responses/${saved.id}.json').exists(),
      isFalse,
    );
  });

  test(
    'body save collision preserves evidence without false completion',
    () async {
      var calls = 0;
      var completions = 0;
      late File retained;
      await expectLater(
        WritingAssistant.stream(
          plan: requestPlan(),
          model: 'synthetic-only',
          useEngine: false,
          transportOverride: (_) async* {
            calls++;
            final saved = await record();
            await Directory('${root.path}/.shufang/responses').create();
            retained = File('${root.path}/.shufang/responses/${saved.id}.json');
            await retained.writeAsString('keep-original-evidence', flush: true);
            yield content;
            yield done;
          },
          onCompleted: (_) => completions++,
        ).toList(),
        throwsStateError,
      );
      final saved = await record();
      expect(saved.state, 'dispatching');
      expect(saved.active, isFalse);
      expect(await retained.readAsString(), 'keep-original-evidence');
      expect(completions, 0);
      expect(calls, 1);
      expect(
        (await WritingResponseStore.readCompleted(
          root: root.path,
          record: saved,
        )).canCopy,
        isFalse,
      );
    },
  );

  test(
    'workspace switch rejects late done and does not save to new root',
    () async {
      final other = await Directory('${root.path}/other').create();
      var calls = 0;
      await expectLater(
        WritingAssistant.stream(
          plan: requestPlan(),
          model: 'synthetic-only',
          useEngine: true,
          transportOverride: (_) async* {
            calls++;
            yield content;
            localDataSource.selectWorkspace(other.path, isPrimary: false);
            yield done;
          },
        ).toList(),
        throwsStateError,
      );
      final saved = await record();
      expect(saved.state, 'failed');
      expect(calls, 1);
      expect(await Directory('${other.path}/.shufang').exists(), isFalse);
      expect(
        await File('${root.path}/.shufang/responses/${saved.id}.json').exists(),
        isFalse,
      );
    },
  );
}

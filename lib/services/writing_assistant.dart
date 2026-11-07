import '../api/api_client.dart';
import '../api/api_routes.dart';
import '../store/local_data_source.dart';
import 'direct_llm_client.dart';
import 'writing_context.dart';
import 'writing_request_ledger.dart';

typedef WritingTransport =
    Stream<DirectLlmEvent> Function(
      void Function(Map<String, dynamic>) onReceipt,
    );

/// Both transports receive the same frozen request. The new endpoint cannot
/// silently fall back to an older server that re-reads a different manuscript.
class WritingAssistant {
  static Stream<DirectLlmEvent> stream({
    required WritingContextPlan plan,
    required String model,
    required bool useEngine,
    WritingTransport? transportOverride,
    void Function(WritingRequestCompletion completion)? onCompleted,
  }) async* {
    if (!localDataSource.hasWorkspace) throw StateError('请先选择工作区。');
    final revision = localDataSource.sessionRevision;
    final root = localDataSource.storageRoot;
    final run = await WritingRequestLedger.begin(
      root: root,
      plan: plan,
      model: model,
      useEngine: useEngine,
    );
    final receipt = <String, dynamic>{};
    var output = '';
    var journalFailed = false;
    void collect(Map<String, dynamic> data) => receipt.addAll(data);
    try {
      if (revision != localDataSource.sessionRevision) {
        throw StateError('工作区已切换，原请求未发送。');
      }
      await run.dispatch();
      if (revision != localDataSource.sessionRevision) {
        throw StateError('工作区已切换，原请求未发送。');
      }
      final stream =
          transportOverride != null
              ? transportOverride(collect)
              : _transport(plan, model, useEngine, run.id, collect);
      await for (final event in stream.timeout(const Duration(seconds: 90))) {
        if (revision != localDataSource.sessionRevision) {
          throw StateError('工作区已切换，本地已停止接收；服务端状态未知。');
        }
        if (event.type == DirectLlmEventType.error) {
          throw StateError('生成未完成：${event.content}');
        }
        if (event.type == DirectLlmEventType.content) {
          output += event.content;
          if (output.length > 128000) throw StateError('回复超过本地接收上限。');
        }
        if (event.type == DirectLlmEventType.done) {
          if (output.trim().isEmpty) throw StateError('服务未返回有效正文。');
          WritingRequestCompletion? completion;
          try {
            completion = await run.finish(
              'completed',
              output: output,
              receipt: receipt,
            );
          } catch (_) {
            journalFailed = true;
            throw StateError('回复已收到，但完成记录写入失败。请先核查调用记录，避免重复付费。');
          }
          if (revision != localDataSource.sessionRevision) {
            throw StateError('工作区已切换，原调用记录已保留，未关联到新工作区。');
          }
          onCompleted?.call(completion!);
          yield event;
          return;
        }
        yield event;
      }
      throw StateError('连接在完成回执前结束。');
    } catch (error) {
      if (!run.terminal && !journalFailed) {
        journalFailed = true;
        await run.finish(
          run.dispatched ? 'failed' : 'interrupted',
          output: output,
          receipt: receipt,
        );
      }
      rethrow;
    } finally {
      if (!run.terminal && !journalFailed) {
        // Cancelling local listening does not confirm server cancellation.
        await run.finish('interrupted', output: output, receipt: receipt);
      }
    }
  }

  static Stream<DirectLlmEvent> _transport(
    WritingContextPlan plan,
    String model,
    bool useEngine,
    String requestId,
    void Function(Map<String, dynamic>) collect,
  ) async* {
    if (useEngine) {
      try {
        await for (final event in apiClient
            .ssePostEvents(
              ApiRoutes.chatContextSend,
              body: {
                'request_id': requestId,
                'model': model,
                'context_packet': plan.toPacket(),
              },
              requireComplete: true,
              onReceipt: collect,
            )
            .timeout(const Duration(seconds: 90))) {
          switch (event.type) {
            case SseEventType.content:
              yield DirectLlmEvent(
                type: DirectLlmEventType.content,
                content: event.content,
              );
            case SseEventType.reasoning:
              yield DirectLlmEvent(
                type: DirectLlmEventType.reasoning,
                content: event.content,
              );
            case SseEventType.error:
              throw StateError(event.content);
            case SseEventType.done:
              yield const DirectLlmEvent(type: DirectLlmEventType.done);
              return;
            case SseEventType.warning:
              break;
          }
        }
        throw StateError('引擎未返回生成内容');
      } catch (error) {
        // Once an engine request was sent, a zero-output failure cannot prove
        // that the provider did not charge it. Do not silently issue a second
        // paid generation through the direct client. The UI can expose this
        // as a settlement-unknown retry decision.
        throw StateError('引擎请求未完成，结算状态未知：$error');
      }
    }
    yield* DirectLlmClient.streamChat(
      messages: plan.messages,
      model: model,
      requireComplete: true,
      onReceipt: collect,
    ).timeout(const Duration(seconds: 90));
  }
}

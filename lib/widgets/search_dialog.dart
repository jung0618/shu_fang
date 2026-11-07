import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_routes.dart';
import '../services/editor_request_lease.dart';
import '../store/editor_store.dart';

/// 跨章搜索对话框
class SearchDialog extends ConsumerStatefulWidget {
  const SearchDialog({super.key});

  @override
  ConsumerState<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends ConsumerState<SearchDialog> {
  final _queryController = TextEditingController();
  int _requestSerial = 0;

  @override
  void dispose() {
    _requestSerial++;
    _queryController.dispose();
    // D50-6 (M2): 关闭搜索对话框时清空搜索状态, 避免切书后旧结果残留
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(searchResultsProvider.notifier).state = [];
    ref.read(searchLoadingProvider.notifier).state = false;
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _queryController.text.trim();
    if (q.isEmpty) return;
    final lease = EditorRequestLease(ref);
    final serial = ++_requestSerial;
    final book = ref.read(currentBookProvider);
    ref.read(searchLoadingProvider.notifier).state = true;
    ref.read(searchQueryProvider.notifier).state = q;
    try {
      final res = await apiClient.post(
        ApiRoutes.search,
        body: {'query': q, if (book != null) 'book': book, 'limit': 50},
      );
      if (!lease.isCurrent || serial != _requestSerial) return;
      final list = (res.data?['results'] as List?) ?? [];
      ref.read(searchResultsProvider.notifier).state =
          list
              .map((j) => SearchResult.fromJson(j as Map<String, dynamic>))
              .toList();
    } catch (e) {
      if (mounted && lease.isCurrent && serial == _requestSerial) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('搜索失败: $e')));
      }
    } finally {
      if (lease.isCurrent && serial == _requestSerial) {
        ref.read(searchLoadingProvider.notifier).state = false;
      }
    }
  }

  // D37 Phase 2-3 (P1-7): 修复搜索结果断流
  // 之前只 set currentChapter, 不开 Buffer 不跳路由 → 编辑器不显示结果章节
  // 现在: set book + chapter + 开 Buffer + 跳 editor 路由
  void _openResult(SearchResult r) {
    final currentBook = ref.read(currentBookProvider);
    // 搜索结果可能来自不同书, 这里需要切到对应书 (SearchResult 含 bookId 字段则用, 否则用当前书)
    final bookId = r.bookId.isNotEmpty ? r.bookId : (currentBook ?? '');
    if (bookId.isEmpty) return;
    ref.read(currentBookProvider.notifier).state = bookId;
    ref.read(currentChapterProvider.notifier).state = r.chapterId;
    // 开 Buffer (让编辑器 Tab 栏显示该章节)
    BufferActions.open(
      ref,
      bookId: bookId,
      chapterId: r.chapterId,
      title: r.title,
    );
    // 跳到编辑器路由 (之前缺失, 导致搜索点了不进正文)
    ref.read(appRouteProvider.notifier).state = AppRoute.editor;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(searchLoadingProvider);
    final results = ref.watch(searchResultsProvider);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.search),
                  const SizedBox(width: 8),
                  Text('跨章搜索', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _queryController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '输入关键词 (正则需后端支持)',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _runSearch,
                  ),
                ),
                onSubmitted: (_) => _runSearch(),
              ),
              const SizedBox(height: 12),
              if (loading) const LinearProgressIndicator(),
              if (!loading && results.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      '暂无结果',
                      style: TextStyle(color: Theme.of(context).disabledColor),
                    ),
                  ),
                ),
              if (results.isNotEmpty)
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = results[i];
                      return ExpansionTile(
                        title: Text(
                          r.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        subtitle: Text(
                          '${r.matches.length} 处匹配',
                          style: const TextStyle(fontSize: 12),
                        ),
                        initiallyExpanded: i == 0,
                        children:
                            r.matches.map((m) {
                              return ListTile(
                                dense: true,
                                leading: Text(
                                  'L${m.line}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                title: Text(
                                  m.snippet,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                onTap: () => _openResult(r),
                              );
                            }).toList(),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

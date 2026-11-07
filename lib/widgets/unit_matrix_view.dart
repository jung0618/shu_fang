import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../store/editor_store.dart';

/// 章节 × 单元集 匹配矩阵
class UnitMatrixView extends ConsumerStatefulWidget {
  const UnitMatrixView({super.key});

  @override
  ConsumerState<UnitMatrixView> createState() => _UnitMatrixViewState();
}

class _UnitMatrixViewState extends ConsumerState<UnitMatrixView> {
  String? _book;
  final Set<String> _chapterIds = {};

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);
    final setsAsync = ref.watch(unitSetsProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 书籍选择
          booksAsync.when(
            data: (books) => Row(
              children: [
                const Text('书籍:', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _book,
                  hint: const Text('选择书籍'),
                  items: books
                      .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _book = v;
                    _chapterIds.clear();
                  }),
                ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Text('books 错误: $e'),
          ),
          const SizedBox(height: 12),
          // 章节多选
          if (_book != null)
            booksAsync.when(
              data: (books) {
                final book = books.firstWhere(
                  (b) => b.id == _book,
                  orElse: () => const BookInfo(id: '', name: ''),
                );
                if (book.chapters.isEmpty) {
                  return const Text('该书无章节');
                }
                return Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final c in book.chapters)
                      FilterChip(
                        label: Text(c.title, style: const TextStyle(fontSize: 11)),
                        selected: _chapterIds.contains(c.id),
                        onSelected: (v) => setState(() {
                          if (v) {
                            _chapterIds.add(c.id);
                          } else {
                            _chapterIds.remove(c.id);
                          }
                        }),
                      ),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('$e'),
            ),
          const SizedBox(height: 16),
          const Divider(),
          // 矩阵
          Expanded(
            child: (_chapterIds.isEmpty || _book == null)
                ? const Center(child: Text('选择至少一个章节以查看矩阵'))
                : setsAsync.when(
                    data: (sets) {
                      if (sets.isEmpty) {
                        return const Center(child: Text('尚无单元集'));
                      }
                      final matrixAsync = ref.watch(
                        unitrefMatrixProvider(MatrixKey(_book!, _chapterIds.toList())),
                      );
                      return matrixAsync.when(
                        data: (matrix) => SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: [
                                const DataColumn(label: Text('章节 \\ 单元集')),
                                for (final s in sets)
                                  DataColumn(label: Text(s.name, style: const TextStyle(fontSize: 11))),
                              ],
                              rows: [
                                for (final cid in _chapterIds)
                                  DataRow(cells: [
                                    DataCell(Text(_titleOf(booksAsync, cid), style: const TextStyle(fontSize: 11))),
                                    for (final s in sets)
                                      DataCell(_matchCell(matrix[cid]?.contains(s.id) ?? false)),
                                  ]),
                              ],
                            ),
                          ),
                        ),
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('矩阵加载失败: $e')),
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('单元集加载失败: $e')),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _matchCell(bool matched) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: matched ? Colors.green : Colors.transparent,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: matched ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
    );
  }

  String _titleOf(AsyncValue<List<BookInfo>> booksAsync, String chapterId) {
    final books = booksAsync.asData?.value;
    if (books == null) return chapterId;
    for (final b in books) {
      for (final c in b.chapters) {
        if (c.id == chapterId) return c.title;
      }
    }
    return chapterId;
  }
}

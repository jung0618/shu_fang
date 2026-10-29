import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/chapter_save_queue.dart';
import '../services/safe_file_writer.dart';
import '../services/workspace_catalog.dart';
import 'local_data_source.dart';
import 'local_prefs.dart';

export '../services/workspace_catalog.dart'
    show LocalWorkspace, WorkspaceCatalog;

class WorkspaceState {
  final LocalWorkspace? workspace;
  final bool isLoading;
  final String? error;
  // Distinguishes a reopened directory from its previous editor session.
  final int revision;
  const WorkspaceState({
    this.workspace,
    this.isLoading = false,
    this.error,
    this.revision = 0,
  });
}

class WorkspaceController extends StateNotifier<WorkspaceState> {
  WorkspaceController() : super(const WorkspaceState());
  String? get error => state.error;

  Future<bool> open(String id) => _open(id: id);
  Future<bool> create(String name) => _open(name: name);

  Future<bool> _open({String? id, String? name}) async {
    if (state.isLoading) return false;
    final old = state;
    state = WorkspaceState(
      workspace: old.workspace,
      isLoading: true,
      revision: old.revision,
    );
    try {
      // Let focus loss finish any composing input before saving the editor.
      await Future<void>.delayed(Duration.zero);
      if (!await chapterSaveQueue.flushAll()) {
        throw const FileSystemException('还有正文或标记未保存，请返回写作并按 Ctrl+S 重试。');
      }
      await SafeFileWriter.flushAll();
      final LocalWorkspace workspace;
      if (name != null) {
        workspace = await WorkspaceCatalog.create(name);
      } else {
        final catalog = await WorkspaceCatalog.discover();
        workspace = catalog.firstWhere((item) => item.id == id);
      }
      await Directory(
        '${workspace.path}${Platform.pathSeparator}books',
      ).create(recursive: true);
      await PrefsController.update(
        PrefsController.current.copyWith(lastWorkspaceId: workspace.id),
      );
      if (!mounted) return false;
      chapterSaveQueue.releaseSavedDrafts();
      localDataSource.selectWorkspace(
        workspace.path,
        isPrimary: workspace.isPrimary,
      );
      state = WorkspaceState(workspace: workspace, revision: old.revision + 1);
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = WorkspaceState(
        workspace: old.workspace,
        revision: old.revision,
        error: '无法打开工作区：$e',
      );
      return false;
    }
  }

  /// Keep the editor and every failed draft alive when saving fails.
  Future<bool> leave() async {
    if (state.isLoading) return false;
    final old = state;
    state = WorkspaceState(
      workspace: old.workspace,
      isLoading: true,
      revision: old.revision,
    );
    try {
      await Future<void>.delayed(Duration.zero);
      if (!await chapterSaveQueue.flushAll()) {
        throw const FileSystemException('还有正文或标记未保存，请按 Ctrl+S 重试后再切换。');
      }
      await SafeFileWriter.flushAll();
      if (!mounted) return false;
      chapterSaveQueue.releaseSavedDrafts();
      localDataSource.clearUser();
      state = WorkspaceState(revision: old.revision + 1);
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = WorkspaceState(
        workspace: old.workspace,
        revision: old.revision,
        error: '工作区未切换：$e',
      );
      return false;
    }
  }
}

final workspaceControllerProvider =
    StateNotifierProvider<WorkspaceController, WorkspaceState>(
      (ref) => WorkspaceController(),
    );
final currentWorkspaceProvider = Provider<LocalWorkspace?>(
  (ref) => ref.watch(workspaceControllerProvider).workspace,
);
final workspaceCatalogProvider =
    FutureProvider.autoDispose<List<LocalWorkspace>>(
      (ref) => WorkspaceCatalog.discover(),
    );

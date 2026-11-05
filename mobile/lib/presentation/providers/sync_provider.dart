import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/local/sync_queue_data_source.dart';
import '../../data/datasources/remote/api_client.dart';
import '../../data/datasources/remote/sync_remote_data_source.dart';
import '../../data/sync/sync_engine.dart';
import 'auth_provider.dart';
import 'notes_provider.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

final syncQueueProvider = Provider<SyncQueueDataSource>((ref) {
  final authState = ref.watch(authProvider);
  final userId = authState.user?.id ?? authState.user?.email;
  return SyncQueueDataSource(userId: userId);
});

final syncRemoteDataSourceProvider = Provider<SyncRemoteDataSource>((ref) {
  final client = ref.watch(apiClientProvider);
  return SyncRemoteDataSource(client);
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final authState = ref.watch(authProvider);
  final userId = authState.user?.id ?? authState.user?.email;
  final notesRepo = ref.watch(notesRepositoryProvider);
  final queue = ref.watch(syncQueueProvider);
  final remote = ref.watch(syncRemoteDataSourceProvider);
  final client = ref.watch(apiClientProvider);

  return SyncEngine(
    userId: userId,
    notesRepository: notesRepo,
    syncQueue: queue,
    remoteDataSource: remote,
    apiClient: client,
  );
});

class SyncState {
  final bool isSyncing;
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final SyncReport? lastReport;
  final String? errorMessage;

  const SyncState({
    this.isSyncing = false,
    this.pendingCount = 0,
    this.lastSyncedAt,
    this.lastReport,
    this.errorMessage,
  });

  SyncState copyWith({
    bool? isSyncing,
    int? pendingCount,
    DateTime? lastSyncedAt,
    SyncReport? lastReport,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastReport: lastReport ?? this.lastReport,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class SyncNotifier extends StateNotifier<SyncState> {
  final SyncEngine _engine;
  final Ref _ref;

  SyncNotifier(this._engine, this._ref) : super(const SyncState()) {
    checkPendingCount();
  }

  Future<void> checkPendingCount() async {
    final count = await _engine.getPendingOperationsCount();
    state = state.copyWith(pendingCount: count);
  }

  Future<SyncReport> syncNow() async {
    state = state.copyWith(isSyncing: true, clearError: true);
    final report = await _engine.synchronize();

    final remaining = await _engine.getPendingOperationsCount();

    state = state.copyWith(
      isSyncing: false,
      lastSyncedAt: report.isSuccess ? DateTime.now() : state.lastSyncedAt,
      pendingCount: remaining,
      lastReport: report,
      errorMessage: report.isSuccess ? null : report.errorMessage,
    );

    // Refresh notes list after sync pull/push
    await _ref.read(notesListProvider.notifier).loadNotes();

    return report;
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return SyncNotifier(engine, ref);
});

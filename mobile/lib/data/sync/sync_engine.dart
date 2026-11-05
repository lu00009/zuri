import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../domain/entities/note.dart';
import '../datasources/local/sync_queue_data_source.dart';
import '../datasources/remote/api_client.dart';
import '../datasources/remote/sync_remote_data_source.dart';
import '../repositories/notes_repository.dart';

class SyncReport {
  final int pushedCount;
  final int conflictCount;
  final int pulledCount;
  final bool isSuccess;
  final String? errorMessage;

  const SyncReport({
    this.pushedCount = 0,
    this.conflictCount = 0,
    this.pulledCount = 0,
    this.isSuccess = true,
    this.errorMessage,
  });
}

class SyncEngine {
  final String? userId;
  final NotesRepository notesRepository;
  final SyncQueueDataSource syncQueue;
  final SyncRemoteDataSource remoteDataSource;
  final ApiClient apiClient;
  final FlutterSecureStorage storage;

  String get _watermarkKey =>
      'pocketbrain_sync_watermark_${userId != null && userId!.trim().isNotEmpty ? userId!.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_') : "default"}';

  SyncEngine({
    this.userId,
    required this.notesRepository,
    required this.syncQueue,
    required this.remoteDataSource,
    required this.apiClient,
    FlutterSecureStorage? storage,
  }) : storage = storage ?? const FlutterSecureStorage();

  Future<SyncReport> synchronize() async {
    // 1. Verify authentication
    final token = await apiClient.getAccessToken();
    if (token == null || token.isEmpty) {
      return const SyncReport(
        isSuccess: false,
        errorMessage: 'User not authenticated. Please log in to sync.',
      );
    }

    int totalPushed = 0;
    int totalConflicts = 0;
    int totalPulled = 0;

    try {
      // 2. Push Phase
      final pendingOps = await syncQueue.getPendingOperations();
      if (pendingOps.isNotEmpty) {
        final pushResults = await remoteDataSource.pushOperations(pendingOps);

        for (final res in pushResults) {
          if (res.status == 'APPLIED' || res.status == 'IGNORED') {
            await syncQueue.removeOperation(res.opId);
            totalPushed++;

            // If server returned updated version, update local record
            if (res.serverVersion != null) {
              final localNote = await notesRepository.getNoteById(res.entityId);
              if (localNote != null) {
                final updated = localNote.copyWith(serverVersion: res.serverVersion);
                await notesRepository.saveNote(updated, isRemoteSync: true);
              }
            }
          } else if (res.status == 'CONFLICT') {
            // Conflict handling: Preserve user data with sibling note!
            totalConflicts++;
            final localNote = await notesRepository.getNoteById(res.entityId);
            final serverNote = res.conflictNote;

            if (localNote != null && serverNote != null) {
              // 1. Fork local modifications into a preserved conflict note
              final preservedNote = Note.create(
                title: '[Conflict] ${localNote.title}',
                content: localNote.content,
                tags: [...localNote.tags, 'conflict'],
                projectId: localNote.projectId,
              );
              await notesRepository.saveNote(preservedNote, isRemoteSync: false);

              // 2. Overwrite the base note with the authoritative server version
              await notesRepository.saveNote(serverNote, isRemoteSync: true);
            }

            // Remove the conflicting operation from the queue
            await syncQueue.removeOperation(res.opId);
          } else {
            // Error: record failure attempt
            await syncQueue.recordFailure(res.opId, res.message ?? 'Unknown sync push error');
          }
        }
      }

      // 3. Pull Phase
      final watermarkStr = await storage.read(key: _watermarkKey);
      final currentWatermark = int.tryParse(watermarkStr ?? '0') ?? 0;

      final pullResult = await remoteDataSource.pullUpdates(currentWatermark);
      for (final remoteNote in pullResult.notes) {
        if (remoteNote.isDeleted) {
          // Deletion propagation: soft delete locally so it never reappears
          await notesRepository.deleteNote(remoteNote.id, softDelete: true, isRemoteSync: true);
        } else {
          // Update or insert remote note
          await notesRepository.saveNote(remoteNote, isRemoteSync: true);
        }
        totalPulled++;
      }

      // 4. Save new watermark
      await storage.write(
        key: _watermarkKey,
        value: pullResult.watermark.toString(),
      );

      return SyncReport(
        pushedCount: totalPushed,
        conflictCount: totalConflicts,
        pulledCount: totalPulled,
        isSuccess: true,
      );
    } catch (e) {
      return SyncReport(
        pushedCount: totalPushed,
        conflictCount: totalConflicts,
        pulledCount: totalPulled,
        isSuccess: false,
        errorMessage: 'Sync error: $e',
      );
    }
  }

  Future<int> getPendingOperationsCount() async {
    return syncQueue.getPendingCount();
  }

  Future<void> resetWatermark() async {
    await storage.delete(key: _watermarkKey);
  }
}

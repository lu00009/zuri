import '../../../domain/entities/note.dart';
import '../local/sync_queue_data_source.dart';
import 'api_client.dart';

class SyncPushResultItem {
  final String opId;
  final String entityId;
  final String status; // APPLIED, CONFLICT, IGNORED, ERROR
  final int? serverVersion;
  final Note? conflictNote;
  final String? message;

  const SyncPushResultItem({
    required this.opId,
    required this.entityId,
    required this.status,
    this.serverVersion,
    this.conflictNote,
    this.message,
  });
}

class SyncPullResult {
  final List<Note> notes;
  final int watermark;
  final bool hasMore;

  const SyncPullResult({
    required this.notes,
    required this.watermark,
    required this.hasMore,
  });
}

class SyncRemoteDataSource {
  final ApiClient _apiClient;

  SyncRemoteDataSource(this._apiClient);

  Future<List<SyncPushResultItem>> pushOperations(List<SyncOperationRecord> ops) async {
    final payloadList = ops.map((op) => op.toPushPayload()).toList();

    final response = await _apiClient.dio.post(
      '/sync/push',
      data: {'operations': payloadList},
    );

    final data = response.data as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>;

    return results.map((item) {
      final map = item as Map<String, dynamic>;
      Note? conflictNote;
      if (map['conflict_note'] != null) {
        final cnMap = map['conflict_note'] as Map<String, dynamic>;
        final tags = (cnMap['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? [];
        conflictNote = Note(
          id: cnMap['id'] as String,
          title: cnMap['title'] as String? ?? '',
          content: cnMap['content'] as String? ?? '',
          projectId: cnMap['project_id'] as String?,
          tags: tags,
          isPinned: cnMap['is_pinned'] as bool? ?? false,
          isArchived: cnMap['is_archived'] as bool? ?? false,
          isDeleted: cnMap['is_deleted'] as bool? ?? false,
          serverVersion: cnMap['version'] as int? ?? 1,
          createdAt: DateTime.parse(cnMap['created_at'] as String),
          updatedAt: DateTime.parse(cnMap['updated_at'] as String),
        );
      }

      return SyncPushResultItem(
        opId: map['op_id'] as String,
        entityId: map['entity_id'] as String,
        status: map['status'] as String,
        serverVersion: map['server_version'] as int?,
        conflictNote: conflictNote,
        message: map['message'] as String?,
      );
    }).toList();
  }

  Future<SyncPullResult> pullUpdates(int sinceVersion) async {
    final response = await _apiClient.dio.get(
      '/sync/pull',
      queryParameters: {'since_version': sinceVersion},
    );

    final data = response.data as Map<String, dynamic>;
    final watermark = data['server_version_watermark'] as int? ?? sinceVersion;
    final hasMore = data['has_more'] as bool? ?? false;
    final notesRaw = data['notes'] as List<dynamic>;

    final notes = notesRaw.map((item) {
      final map = item as Map<String, dynamic>;
      final tags = (map['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? [];
      return Note(
        id: map['id'] as String,
        title: map['title'] as String? ?? '',
        content: map['content'] as String? ?? '',
        projectId: map['project_id'] as String?,
        tags: tags,
        isPinned: map['is_pinned'] as bool? ?? false,
        isArchived: map['is_archived'] as bool? ?? false,
        isDeleted: map['is_deleted'] as bool? ?? false,
        serverVersion: map['version'] as int? ?? 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
    }).toList();

    return SyncPullResult(notes: notes, watermark: watermark, hasMore: hasMore);
  }
}

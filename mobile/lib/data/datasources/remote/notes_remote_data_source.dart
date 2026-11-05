import '../../../domain/entities/note.dart';
import 'api_client.dart';

class NotesRemoteDataSource {
  final ApiClient _apiClient;

  NotesRemoteDataSource(this._apiClient);

  Future<List<Note>> getNotes({
    bool isArchived = false,
    String? search,
    String? tag,
    String? projectId,
  }) async {
    final queryParams = <String, dynamic>{
      'is_archived': isArchived,
    };
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (tag != null && tag.isNotEmpty) queryParams['tag'] = tag;
    if (projectId != null && projectId.isNotEmpty) queryParams['project_id'] = projectId;

    final response = await _apiClient.dio.get(
      '/notes',
      queryParameters: queryParams,
    );

    final data = response.data as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>;

    return items.map((item) {
      final map = item as Map<String, dynamic>;
      final tagsList = (map['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? [];
      return Note(
        id: map['id'] as String,
        title: map['title'] as String? ?? '',
        content: map['content'] as String? ?? '',
        projectId: map['project_id'] as String?,
        tags: tagsList,
        isPinned: map['is_pinned'] as bool? ?? false,
        isArchived: map['is_archived'] as bool? ?? false,
        isDeleted: map['is_deleted'] as bool? ?? false,
        serverVersion: map['version'] as int? ?? 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
    }).toList();
  }

  Future<Note> createNote(Note note) async {
    final response = await _apiClient.dio.post(
      '/notes',
      data: {
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'project_id': note.projectId,
        'tags': note.tags,
        'is_pinned': note.isPinned,
        'is_archived': note.isArchived,
      },
    );

    final map = response.data as Map<String, dynamic>;
    final tagsList = (map['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? [];
    return Note(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      projectId: map['project_id'] as String?,
      tags: tagsList,
      isPinned: map['is_pinned'] as bool? ?? false,
      isArchived: map['is_archived'] as bool? ?? false,
      isDeleted: map['is_deleted'] as bool? ?? false,
      serverVersion: map['version'] as int? ?? 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Future<void> deleteNote(String id) async {
    await _apiClient.dio.delete('/notes/$id');
  }

  Future<List<String>> getTags() async {
    final response = await _apiClient.dio.get('/notes/tags/all');
    return (response.data as List<dynamic>).map((t) => t.toString()).toList();
  }

  Future<List<String>> getProjects() async {
    final response = await _apiClient.dio.get('/notes/projects/all');
    return (response.data as List<dynamic>).map((p) => p.toString()).toList();
  }
}

import 'dart:convert';

const windowProtocolVersion = 1;

enum WindowMessageType {
  lifecycleReady,
  lifecycleHealth,
  stickyState,
  taskSnapshot,
  taskSnapshotRequest,
  taskCreate,
  taskComplete,
  taskReopen,
  taskTrash,
  taskOpen,
  projectCreate,
  stickySourceChanged,
  stickyPreferencesChanged,
  stickyRefresh,
  openMain,
  openQuickNote,
  noteCreate,
  noteOpen,
  noteUpdate,
  noteAutosave,
  noteManualSave,
  noteRename,
  noteArchive,
  noteTrash,
  noteRestore,
  noteStateSnapshot,
  noteSaveAck,
  geometryChanged,
  vaultState,
  localeChanged,
  themeChanged,
  commandAck,
  error,
}

enum WindowErrorCode {
  malformed,
  unsupportedVersion,
  unknownType,
  invalidPayload,
  unavailable,
  internal,
}

final class WindowEnvelope {
  const WindowEnvelope({
    required this.type,
    required this.requestId,
    required this.sourceWindowId,
    required this.payload,
    required this.timestamp,
    this.protocolVersion = windowProtocolVersion,
  });

  factory WindowEnvelope.fromJson(Map<String, Object?> json) {
    final version = json['protocolVersion'];
    if (version != windowProtocolVersion) {
      throw const WindowProtocolException(
        WindowErrorCode.unsupportedVersion,
        'Unsupported protocol version',
      );
    }
    final typeName = json['type'];
    final requestId = json['requestId'];
    final source = json['sourceWindowId'];
    final payload = json['payload'];
    final timestamp = json['timestamp'];
    if (typeName is! String ||
        requestId is! String ||
        requestId.isEmpty ||
        source is! String ||
        source.isEmpty ||
        payload is! Map<String, dynamic> ||
        timestamp is! String) {
      throw const WindowProtocolException(
        WindowErrorCode.malformed,
        'Required envelope field is invalid',
      );
    }
    WindowMessageType type;
    try {
      type = WindowMessageType.values.byName(typeName);
    } on ArgumentError {
      throw const WindowProtocolException(
        WindowErrorCode.unknownType,
        'Unknown command type',
      );
    }
    final parsedTime = DateTime.tryParse(timestamp);
    if (parsedTime == null) {
      throw const WindowProtocolException(
        WindowErrorCode.malformed,
        'Timestamp is invalid',
      );
    }
    _validatePayload(type, payload);
    return WindowEnvelope(
      type: type,
      requestId: requestId,
      sourceWindowId: source,
      payload: payload,
      timestamp: parsedTime,
    );
  }

  factory WindowEnvelope.decode(String value) {
    Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      throw const WindowProtocolException(
        WindowErrorCode.malformed,
        'Message is not valid JSON',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const WindowProtocolException(
        WindowErrorCode.malformed,
        'Message must be an object',
      );
    }
    return WindowEnvelope.fromJson(decoded);
  }

  final int protocolVersion;
  final WindowMessageType type;
  final String requestId;
  final String sourceWindowId;
  final Map<String, Object?> payload;
  final DateTime timestamp;

  Map<String, Object?> toJson() => {
    'protocolVersion': protocolVersion,
    'type': type.name,
    'requestId': requestId,
    'sourceWindowId': sourceWindowId,
    'payload': payload,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  static void _validatePayload(
    WindowMessageType type,
    Map<String, Object?> payload,
  ) {
    if (type == WindowMessageType.geometryChanged) {
      for (final key in ['x', 'y', 'width', 'height']) {
        if (payload[key] is! num) {
          throw const WindowProtocolException(
            WindowErrorCode.invalidPayload,
            'Geometry requires numeric bounds',
          );
        }
      }
    }
    if (type == WindowMessageType.commandAck &&
        (payload['ok'] is! bool || payload['requestId'] is! String)) {
      throw const WindowProtocolException(
        WindowErrorCode.invalidPayload,
        'Acknowledgement payload is invalid',
      );
    }
    if (type == WindowMessageType.taskCreate &&
        (payload['title'] is! String ||
            (payload['title'] as String).trim().isEmpty)) {
      throw const WindowProtocolException(
        WindowErrorCode.invalidPayload,
        'Task creation requires a non-empty title',
      );
    }
    if (type == WindowMessageType.projectCreate &&
        (payload['name'] is! String ||
            (payload['name'] as String).trim().isEmpty)) {
      throw const WindowProtocolException(
        WindowErrorCode.invalidPayload,
        'Project creation requires a non-empty name',
      );
    }
    if ((type == WindowMessageType.taskComplete ||
            type == WindowMessageType.taskReopen ||
            type == WindowMessageType.taskTrash ||
            type == WindowMessageType.taskOpen) &&
        (payload['id'] is! String || payload['revision'] is! int)) {
      throw const WindowProtocolException(
        WindowErrorCode.invalidPayload,
        'Task command requires an id and revision',
      );
    }
    if (type == WindowMessageType.localeChanged &&
        payload['locale'] is! String) {
      throw const WindowProtocolException(
        WindowErrorCode.invalidPayload,
        'Locale change requires a locale code',
      );
    }
    if (type == WindowMessageType.themeChanged &&
        payload['themeId'] is! String) {
      throw const WindowProtocolException(
        WindowErrorCode.invalidPayload,
        'Theme change requires a themeId',
      );
    }
    if (type == WindowMessageType.stickySourceChanged) {
      final source = payload['source'];
      if (source is! String ||
          !StickySourceType.values.any((value) => value.name == source) ||
          (payload['sourceId'] != null && payload['sourceId'] is! String)) {
        throw const WindowProtocolException(
          WindowErrorCode.invalidPayload,
          'Sticky source is invalid.',
        );
      }
    }
    if (type == WindowMessageType.stickyPreferencesChanged &&
        (payload['source'] is! String ||
            !StickySourceType.values.any(
              (value) => value.name == payload['source'],
            ) ||
            (payload['sourceId'] != null && payload['sourceId'] is! String) ||
            payload['opacity'] is! num ||
            payload['compact'] is! bool ||
            payload['showMetadata'] is! bool ||
            payload['collapseCompleted'] is! bool ||
            payload['borderless'] is! bool)) {
      throw const WindowProtocolException(
        WindowErrorCode.invalidPayload,
        'Sticky preferences are invalid.',
      );
    }
    if (type == WindowMessageType.noteCreate &&
        (payload['title'] is! String || payload['body'] is! String)) {
      throw const WindowProtocolException(
        WindowErrorCode.invalidPayload,
        'Note creation requires title and body.',
      );
    }
    if (type == WindowMessageType.noteOpen && payload['id'] is! String) {
      throw const WindowProtocolException(
        WindowErrorCode.invalidPayload,
        'Note open requires an id.',
      );
    }
    if (type == WindowMessageType.noteRename &&
        (payload['id'] is! String ||
            payload['title'] is! String ||
            payload['revision'] is! int)) {
      throw const WindowProtocolException(
        WindowErrorCode.invalidPayload,
        'Note rename requires an id, title, and revision.',
      );
    }
    if ((type == WindowMessageType.noteArchive ||
            type == WindowMessageType.noteTrash ||
            type == WindowMessageType.noteRestore) &&
        (payload['id'] is! String || payload['revision'] is! int)) {
      throw const WindowProtocolException(
        WindowErrorCode.invalidPayload,
        'Note lifecycle command requires an id and revision.',
      );
    }
    if (type == WindowMessageType.noteUpdate ||
        type == WindowMessageType.noteAutosave ||
        type == WindowMessageType.noteManualSave) {
      if (payload['id'] is! String ||
          payload['title'] is! String ||
          payload['body'] is! String ||
          payload['revision'] is! int ||
          payload['saveGeneration'] is! int) {
        throw const WindowProtocolException(
          WindowErrorCode.invalidPayload,
          'Note save payload is invalid.',
        );
      }
    }
    if (type == WindowMessageType.noteStateSnapshot &&
        (payload['id'] is! String ||
            payload['title'] is! String ||
            payload['body'] is! String ||
            payload['revision'] is! int ||
            payload['saveGeneration'] is! int)) {
      throw const WindowProtocolException(
        WindowErrorCode.invalidPayload,
        'Note snapshot payload is invalid.',
      );
    }
    if (type == WindowMessageType.noteSaveAck &&
        (payload['id'] is! String ||
            payload['revision'] is! int ||
            payload['saveGeneration'] is! int)) {
      throw const WindowProtocolException(
        WindowErrorCode.invalidPayload,
        'Note save acknowledgement is invalid.',
      );
    }
    if (type == WindowMessageType.taskSnapshot) {
      if (payload['sequence'] is! int ||
          payload['vaultId'] is! String ||
          payload['tasks'] is! List) {
        throw const WindowProtocolException(
          WindowErrorCode.invalidPayload,
          'Task snapshot payload is invalid',
        );
      }
      for (final item in payload['tasks'] as List) {
        if (item is! Map ||
            item['id'] is! String ||
            item['title'] is! String ||
            item['priority'] is! String ||
            item['completed'] is! bool ||
            item['revision'] is! int ||
            (item['due'] != null && item['due'] is! String) ||
            (item['project'] != null && item['project'] is! String)) {
          throw const WindowProtocolException(
            WindowErrorCode.invalidPayload,
            'Task snapshot item is invalid',
          );
        }
      }
    }
  }
}

final class StickyTaskSnapshotItem {
  const StickyTaskSnapshotItem({
    required this.id,
    required this.title,
    required this.priority,
    required this.completed,
    required this.revision,
    this.due,
    this.project,
  });

  factory StickyTaskSnapshotItem.fromJson(Map<Object?, Object?> json) =>
      StickyTaskSnapshotItem(
        id: json['id']! as String,
        title: json['title']! as String,
        priority: json['priority']! as String,
        completed: json['completed']! as bool,
        revision: json['revision']! as int,
        due: json['due'] as String?,
        project: json['project'] as String?,
      );

  final String id;
  final String title;
  final String priority;
  final bool completed;
  final int revision;
  final String? due;
  final String? project;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'priority': priority,
    'completed': completed,
    'revision': revision,
    'due': due,
    'project': project,
  };
}

final class StickyTaskSnapshot {
  const StickyTaskSnapshot({
    required this.sequence,
    required this.vaultId,
    required this.tasks,
  });

  factory StickyTaskSnapshot.fromPayload(Map<String, Object?> payload) =>
      StickyTaskSnapshot(
        sequence: payload['sequence']! as int,
        vaultId: payload['vaultId']! as String,
        tasks: (payload['tasks']! as List)
            .map(
              (item) => StickyTaskSnapshotItem.fromJson(
                item as Map<Object?, Object?>,
              ),
            )
            .toList(),
      );

  final int sequence;
  final String vaultId;
  final List<StickyTaskSnapshotItem> tasks;

  Map<String, Object?> toPayload() => {
    'sequence': sequence,
    'vaultId': vaultId,
    'tasks': tasks.map((task) => task.toJson()).toList(),
  };
}

enum StickySourceType {
  today,
  tomorrow,
  thisWeek,
  project,
  folderOrList,
  pinned,
  savedFilter,
}

final class StickyPreferences {
  const StickyPreferences({
    this.source = StickySourceType.today,
    this.sourceId,
    this.opacity = 0.96,
    this.compact = false,
    this.showMetadata = true,
    this.collapseCompleted = false,
    this.borderless = false,
  });

  final StickySourceType source;
  final String? sourceId;
  final double opacity;
  final bool compact;
  final bool showMetadata;
  final bool collapseCompleted;
  final bool borderless;

  double get safeOpacity => opacity.clamp(0.65, 1);

  Map<String, Object?> toJson() => {
    'source': source.name,
    'sourceId': sourceId,
    'opacity': safeOpacity,
    'compact': compact,
    'showMetadata': showMetadata,
    'collapseCompleted': collapseCompleted,
    'borderless': borderless,
  };

  factory StickyPreferences.fromJson(Map<String, Object?> json) =>
      StickyPreferences(
        source: StickySourceType.values.firstWhere(
          (value) => value.name == json['source'],
          orElse: () => StickySourceType.today,
        ),
        sourceId: json['sourceId'] as String?,
        opacity: ((json['opacity'] as num?)?.toDouble() ?? .96).clamp(.65, 1),
        compact: json['compact'] as bool? ?? false,
        showMetadata: json['showMetadata'] as bool? ?? true,
        collapseCompleted: json['collapseCompleted'] as bool? ?? false,
        borderless: json['borderless'] as bool? ?? false,
      );
}

final class WindowProtocolException implements Exception {
  const WindowProtocolException(this.code, this.message);
  final WindowErrorCode code;
  final String message;
}

final class WindowGeometry {
  const WindowGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
  final double x;
  final double y;
  final double width;
  final double height;

  bool get isValid =>
      width >= 280 &&
      height >= 200 &&
      width <= 4000 &&
      height <= 4000 &&
      x.isFinite &&
      y.isFinite;

  Map<String, Object?> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  factory WindowGeometry.fromJson(Map<String, Object?> json) {
    final geometry = WindowGeometry(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );
    if (!geometry.isValid) {
      throw const WindowProtocolException(
        WindowErrorCode.invalidPayload,
        'Geometry is outside supported bounds',
      );
    }
    return geometry;
  }
}

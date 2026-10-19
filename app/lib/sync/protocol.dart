typedef Json = Map<String, Object?>;

class Operation {
  final String operationId, entityType, entityId, kind, createdAt;
  final int localSequence;
  final Json changes;
  final List<String> dependsOn;
  Operation({
    required this.operationId,
    required this.entityType,
    required this.entityId,
    required this.kind,
    required this.createdAt,
    required this.localSequence,
    required Json changes,
    List<String> dependsOn = const [],
  }) : changes = Map.unmodifiable(changes),
       dependsOn = List.unmodifiable(dependsOn);
  factory Operation.fromJson(Json j) => Operation(
    operationId: j['operationId'] as String,
    entityType: j['entityType'] as String,
    entityId: j['entityId'] as String,
    kind: j['kind'] as String,
    createdAt: j['createdAt'] as String,
    localSequence: j['localSequence'] as int,
    changes: Map<String, Object?>.from(j['changes'] as Map),
    dependsOn: (j['dependsOn'] as List).cast<String>(),
  );
  Json toJson() => {
    'operationId': operationId,
    'localSequence': localSequence,
    'entityType': entityType,
    'entityId': entityId,
    'kind': kind,
    'changes': changes,
    'dependsOn': dependsOn,
    'createdAt': createdAt,
  };
  Operation remap(String id) =>
      Operation.fromJson({...toJson(), 'entityId': id});
}

class SyncRequest {
  final String deviceId;
  final String? expectedWorkspaceId;
  final int cursor;
  final List<Operation> operations;
  SyncRequest({
    required this.deviceId,
    this.expectedWorkspaceId,
    required this.cursor,
    required List<Operation> operations,
  }) : operations = List.unmodifiable(operations);
  factory SyncRequest.fromJson(Json j) => SyncRequest(
    deviceId: j['deviceId'] as String,
    expectedWorkspaceId: j['expectedWorkspaceId'] as String?,
    cursor: j['cursor'] as int,
    operations: (j['operations'] as List)
        .map((o) => Operation.fromJson(Map<String, Object?>.from(o as Map)))
        .toList(),
  );
  Json toJson() => {
    'protocolVersion': 1,
    'deviceId': deviceId,
    if (expectedWorkspaceId != null) 'expectedWorkspaceId': expectedWorkspaceId,
    'cursor': cursor,
    'operations': operations.map((o) => o.toJson()).toList(),
  };
}

class Acknowledgement {
  final String operationId, status;
  final String? code;
  final Json? effect;
  Acknowledgement.fromJson(Json j)
    : operationId = j['operationId'] as String,
      status = j['status'] as String,
      code = j['code'] as String?,
      effect = j['effect'] == null
          ? null
          : Map.unmodifiable(j['effect'] as Map<String, Object?>);
  Json toJson() => {
    'operationId': operationId,
    'status': status,
    if (code != null) 'code': code,
    if (effect != null) 'effect': effect,
  };
}

class EntityChange {
  final String entityType, entityId;
  final int revision;
  final Json value;
  EntityChange.fromJson(Json j)
    : entityType = j['entityType'] as String,
      entityId = j['entityId'] as String,
      revision = j['revision'] as int,
      value = Map.unmodifiable(j['value'] as Map<String, Object?>);
  Json toJson() => {
    'entityType': entityType,
    'entityId': entityId,
    'revision': revision,
    'value': value,
  };
}

class SyncResponse {
  final String workspaceId;
  final List<Acknowledgement> acknowledgements;
  final List<EntityChange> changes;
  final int nextCursor;
  final bool hasMore;
  SyncResponse({
    required this.workspaceId,
    required this.acknowledgements,
    required this.changes,
    required this.nextCursor,
    required this.hasMore,
  });
  factory SyncResponse.fromJson(Json j) {
    if (j['protocolVersion'] != 1) {
      throw const FormatException('Неподдерживаемая версия обмена');
    }
    return SyncResponse(
      workspaceId: j['workspaceId'] as String,
      acknowledgements: (j['acknowledgements'] as List)
          .map(
            (a) =>
                Acknowledgement.fromJson(Map<String, Object?>.from(a as Map)),
          )
          .toList(),
      changes: (j['changes'] as List)
          .map(
            (c) => EntityChange.fromJson(Map<String, Object?>.from(c as Map)),
          )
          .toList(),
      nextCursor: j['nextCursor'] as int,
      hasMore: j['hasMore'] as bool,
    );
  }
  Json toJson() => {
    'protocolVersion': 1,
    'workspaceId': workspaceId,
    'acknowledgements': acknowledgements.map((a) => a.toJson()).toList(),
    'changes': changes.map((c) => c.toJson()).toList(),
    'nextCursor': nextCursor,
    'hasMore': hasMore,
  };
}

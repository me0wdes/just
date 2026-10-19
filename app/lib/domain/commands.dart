sealed class TaskCommand {
  const TaskCommand();
  factory TaskCommand.createTask({
    required String id,
    required String title,
    required String listId,
    Map<String, Object?> fields,
  }) = CreateTask;
  factory TaskCommand.patchTask(String id, Map<String, Object?> fields) =
      PatchTask;
  factory TaskCommand.completeTask(String id, String completionDate) =
      CompleteTask;
  factory TaskCommand.undoCompletion(String id, String completionId) =
      UndoCompletion;
  factory TaskCommand.deleteTask(String id) = DeleteTask;
  factory TaskCommand.restoreTask(String id) = RestoreTask;
  factory TaskCommand.createList(String id, String name, {String color}) =
      CreateList;
  factory TaskCommand.patchList(String id, Map<String, Object?> fields) =
      PatchList;
  factory TaskCommand.deleteList(String id) = DeleteList;
  factory TaskCommand.upsertRule(String id, Map<String, Object?> fields) =
      UpsertRule;
  factory TaskCommand.reorderTask(String id, double position) = ReorderTask;
  factory TaskCommand.importEntity(
    String type,
    String id,
    Map<String, Object?> snapshot,
  ) = ImportEntity;
}

final class CreateTask extends TaskCommand {
  final String id, title, listId;
  final Map<String, Object?> fields;
  const CreateTask({
    required this.id,
    required this.title,
    required this.listId,
    this.fields = const {},
  });
}

final class PatchTask extends TaskCommand {
  final String id;
  final Map<String, Object?> fields;
  const PatchTask(this.id, this.fields);
}

final class CompleteTask extends TaskCommand {
  final String id, completionDate;
  const CompleteTask(this.id, this.completionDate);
}

final class UndoCompletion extends TaskCommand {
  final String id, completionId;
  const UndoCompletion(this.id, this.completionId);
}

final class DeleteTask extends TaskCommand {
  final String id;
  const DeleteTask(this.id);
}

final class RestoreTask extends TaskCommand {
  final String id;
  const RestoreTask(this.id);
}

final class CreateList extends TaskCommand {
  final String id, name, color;
  const CreateList(this.id, this.name, {this.color = '#8C9B7A'});
}

final class PatchList extends TaskCommand {
  final String id;
  final Map<String, Object?> fields;
  const PatchList(this.id, this.fields);
}

final class DeleteList extends TaskCommand {
  final String id;
  const DeleteList(this.id);
}

final class UpsertRule extends TaskCommand {
  final String id;
  final Map<String, Object?> fields;
  const UpsertRule(this.id, this.fields);
}

final class ReorderTask extends TaskCommand {
  final String id;
  final double position;
  const ReorderTask(this.id, this.position);
}

final class ImportEntity extends TaskCommand {
  final String type, id;
  final Map<String, Object?> snapshot;
  const ImportEntity(this.type, this.id, this.snapshot);
}

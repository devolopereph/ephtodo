class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.completed,
    required this.updatedAtMicros,
  });

  final String id;
  final String title;
  final bool completed;
  final int updatedAtMicros;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'completed': completed,
    'updatedAtMicros': updatedAtMicros,
  };

  factory TaskItem.fromJson(Map<Object?, Object?> json) => TaskItem(
    id: json['id']! as String,
    title: json['title']! as String,
    completed: json['completed']! as bool,
    updatedAtMicros: json['updatedAtMicros']! as int,
  );
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models.dart';
import '../../platform/feedback_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/chroma_swap.dart';
import '../../theme/controls.dart';
import '../../theme/day_icon.dart';
import '../../theme/day_sound.dart';
import '../../theme/fluid_button.dart';
import '../../theme/fluid_surface.dart';
import '../../theme/motion_tokens.dart';
import '../../theme/segments.dart';
import 'greeting_header.dart';
import 'list_panel.dart';
import 'task_composer.dart';
import 'task_controller.dart';
import 'task_detail_panel.dart';
import 'task_row.dart';

const _weekdays = [
  'понедельник',
  'вторник',
  'среда',
  'четверг',
  'пятница',
  'суббота',
  'воскресенье',
];
const _months = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

String _plural(int n, String one, String few, String many) {
  final d = n % 10, h = n % 100;
  if (d == 1 && h != 11) return one;
  if (d >= 2 && d <= 4 && (h < 12 || h > 14)) return few;
  return many;
}

final _mac = defaultTargetPlatform == TargetPlatform.macOS;

/// Sidebar width on wide windows.
const sidebarWidth = 240.0;

class TaskHome extends StatefulWidget {
  final TaskController controller;
  final VoidCallback? onSettings, onSync;
  final String syncLabel;
  final Future<bool> Function()? onRequestReminder;
  const TaskHome({
    super.key,
    required this.controller,
    this.onSettings,
    this.syncLabel = 'Сохранено на устройстве',
    this.onSync,
    this.onRequestReminder,
  });
  @override
  State<TaskHome> createState() => _TaskHomeState();
}

class _TaskHomeState extends State<TaskHome> {
  Widget reflow(Widget child) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: MotionTokens.reflow,
          curve: MotionTokens.easeOut,
          alignment: Alignment.topCenter,
          child: child,
        );
  final composer = FocusNode(), search = FocusNode();
  final searchText = TextEditingController();
  final scaffold = GlobalKey<ScaffoldState>();
  final scroll = ScrollController();
  bool showCompleted = false;
  final settling = <String>{}, collapsing = <String>{};

  /// Rows present at first paint stay still; rows added later rise in.
  final known = <String>{};
  bool primed = false;
  final motionTimers = <Timer>[];
  TaskController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(_openRequestedTask);
  }

  void _openRequestedTask() {
    final id = c.takeOpenRequest();
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final task = await c.repository.readTask(id);
      if (!mounted || task == null || task.deleted) return;
      c.search('');
      c.navigate(TaskView.all);
      await open(task, MediaQuery.sizeOf(context).width >= 1280);
    });
  }

  @override
  void dispose() {
    c.removeListener(_openRequestedTask);
    composer.dispose();
    search.dispose();
    searchText.dispose();
    scroll.dispose();
    for (final timer in motionTimers) {
      timer.cancel();
    }
    super.dispose();
  }

  Future<void> toggle(TaskItem task) async {
    try {
      if (task.completed) {
        await c.undoCompletion(task.id, task.completionId!);
      } else {
        final reduce = MediaQuery.disableAnimationsOf(context);
        if (!reduce) setState(() => settling.add(task.id));
        await c.completeTask(task.id);
        if (!mounted) return;
        if (!reduce) {
          // Let the tick and the strike finish before the row folds away.
          motionTimers.add(
            Timer(const Duration(milliseconds: 420), () {
              if (!mounted) return;
              setState(() => collapsing.add(task.id));
              motionTimers.add(
                Timer(MotionTokens.reflow, () {
                  if (mounted) {
                    setState(() {
                      settling.remove(task.id);
                      collapsing.remove(task.id);
                      // It rises in on the «Выполненные» tab.
                      known.remove(task.id);
                    });
                  }
                }),
              );
            }),
          );
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              persist: false,
              duration: MotionTokens.toast,
              content: Text('«${task.title}» выполнена'),
              action: SnackBarAction(
                label: 'Вернуть',
                onPressed: () async {
                  final saved = await c.repository.readTask(task.id);
                  if (saved?.completionId != null) {
                    await c.undoCompletion(task.id, saved!.completionId!);
                  }
                },
              ),
            ),
          );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          settling.remove(task.id);
          collapsing.remove(task.id);
        });
        DaySound.play(context, UiSound.error);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            persist: false,
            duration: MotionTokens.toast,
            content: Text('Не удалось изменить задачу'),
          ),
        );
      }
    }
  }

  Future<void> remove(TaskItem task) async {
    final messenger = ScaffoldMessenger.of(context);
    DaySound.play(context, UiSound.delete);
    if (c.selectedId == task.id) c.select(null);
    await c.deleteTask(task.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          duration: MotionTokens.toast,
          content: const Text('Задача удалена'),
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () => c.restoreTask(task.id),
          ),
        ),
      );
  }

  Future<void> open(TaskItem task, bool inline) async {
    if (c.selectedId != task.id) {
      DaySound.play(context, c.selectedId == null ? UiSound.open : UiSound.nav);
    }
    c.select(task.id);
    if (inline) return;
    await showDialog<void>(
      context: context,
      animationStyle: const AnimationStyle(
        duration: MotionTokens.panel,
        reverseDuration: MotionTokens.panel,
        curve: MotionTokens.easeOut,
      ),
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 720),
          child: TaskDetailPanel(
            task: task,
            controller: c,
            onRequestReminder: widget.onRequestReminder,
            onClose: () => Navigator.pop(context),
          ),
        ),
      ),
    );
    if (mounted) {
      DaySound.play(context, UiSound.close);
      c.select(null);
    }
  }

  Widget emptyState(bool completedTab) {
    final colors = DayColors.of(context);
    final searching = c.query.search.isNotEmpty;
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.raised,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border),
                ),
                child: DayIcon(
                  searching
                      ? DayGlyph.search
                      : completedTab
                      ? DayGlyph.check
                      : DayGlyph.sun,
                  size: 26,
                  color: colors.muted,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                searching
                    ? 'Ничего не нашлось'
                    : completedTab
                    ? 'Пока ничего не выполнено'
                    : 'Здесь пока тихо',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                searching
                    ? 'Попробуйте другое слово'
                    : completedTab
                    ? 'Отмеченные задачи появятся здесь'
                    : c.query.view == TaskView.today
                    ? 'Задачи со сроком на сегодня появятся здесь'
                    : 'Добавьте первую задачу внизу',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget taskList(
    List<TaskItem> active,
    List<TaskItem> completed,
    bool desktop,
    bool inline,
  ) {
    if (c.error != null) return Center(child: Text(c.error!));
    if (c.loading) return const Center(child: CircularProgressIndicator());
    final items = showCompleted ? completed : active;
    if (!primed) {
      known.addAll(c.tasks.map((t) => t.id));
      primed = true;
    }
    if (items.isEmpty) return emptyState(showCompleted);
    return ReorderableListView.builder(
      scrollController: scroll,
      buildDefaultDragHandles: false,
      padding: EdgeInsets.zero,
      itemCount: items.length,
      // The dragged card lifts with a soft shadow cut to its own shape;
      // the item's 8px bottom gap stays outside the shadow.
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final t = Curves.easeOut.transform(animation.value);
          return Material(
            type: MaterialType.transparency,
            child: Transform.scale(
              scale: 1 + .015 * t,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .18 * t),
                            blurRadius: 24,
                            offset: Offset(0, 8 * t),
                          ),
                        ],
                      ),
                    ),
                  ),
                  child!,
                ],
              ),
            ),
          );
        },
      ),
      onReorderStart: (_) => DaySound.play(context, UiSound.tap),
      onReorderItem: (oldIndex, newIndex) {
        if (showCompleted || oldIndex >= active.length) return;
        DaySound.play(context, UiSound.nav);
        final copy = List<TaskItem>.of(active), item = active[oldIndex];
        copy.removeAt(oldIndex);
        final target = newIndex.clamp(0, copy.length);
        final before = target == 0
            ? (copy.firstOrNull?.position ?? 1024) - 2048
            : copy[target - 1].position;
        final after = target == copy.length
            ? before + 2048
            : copy[target].position;
        c.reorderTask(item.id, (before + after) / 2);
      },
      itemBuilder: (context, index) {
        final task = items[index];
        final fresh = known.add(task.id);
        final row = TaskRow(
          task: task,
          selected: c.selectedId == task.id,
          today: c.query.today,
          onToggle: () => toggle(task),
          onOpen: () => open(task, inline),
          onMenu: (at) => showDayMenu(context, at, [
            DayMenuItem('Открыть', DayGlyph.note, () => open(task, inline)),
            DayMenuItem(
              task.completed ? 'Вернуть' : 'Выполнить',
              DayGlyph.check,
              () => toggle(task),
            ),
            DayMenuItem(
              'Удалить',
              DayGlyph.delete,
              () => remove(task),
              destructive: true,
            ),
          ]),
        );
        return KeyedSubtree(
          key: ValueKey(task.id),
          child: reflow(
            collapsing.contains(task.id) && task.completed
                ? const SizedBox(height: 0, width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _Appear(
                      animate: fresh,
                      // Desktop drags the card itself once the pointer moves
                      // vertically; a plain click still opens it. Touch
                      // waits for a long press so scrolling stays free.
                      child: desktop
                          ? _CardDrag(
                              index: index,
                              enabled: !task.completed,
                              child: row,
                            )
                          : ReorderableDelayedDragStartListener(
                              index: index,
                              enabled: !task.completed,
                              child: row,
                            ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget searchField() {
    final colors = DayColors.of(context);
    return TextField(
      key: const Key('task-search-input'),
      controller: searchText,
      focusNode: search,
      onChanged: (text) {
        c.search(text);
        setState(() {});
      },
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Поиск',
        isDense: true,
        fillColor: colors.input,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 6),
          child: DayIcon(DayGlyph.search, size: 18, color: colors.muted),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
        suffixIcon: IconButton(
          tooltip: 'Закрыть поиск',
          onPressed: closeSearch,
          icon: DayIcon(DayGlyph.close, size: 16, color: colors.muted),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }

  bool searching = false;
  void openSearch() {
    setState(() => searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => search.requestFocus());
  }

  void closeSearch() {
    searchText.clear();
    c.search('');
    setState(() => searching = false);
  }

  Widget reminderWarning() => OutlinedButton.icon(
    icon: DayIcon(
      DayGlyph.warning,
      size: 16,
      color: Theme.of(context).colorScheme.error,
    ),
    label: Text(
      'Напоминания: ${c.reminderFailures.length}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onPressed: () {
      DaySound.play(context, UiSound.open);
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Напоминания требуют внимания'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final entry in c.reminderFailures.entries)
                  ListTile(
                    title: Text(
                      c.tasks
                              .where((t) => t.id == entry.key)
                              .firstOrNull
                              ?.title ??
                          'Системное напоминание',
                    ),
                    subtitle: Text(entry.value),
                    onTap: entry.key == '*'
                        ? null
                        : () {
                            Navigator.pop(context);
                            c.requestOpen(entry.key);
                          },
                  ),
              ],
            ),
          ),
          actions: [
            FluidButton.text(
              onPressed: () => Navigator.pop(context),
              child: const Text('Понятно'),
            ),
          ],
        ),
      );
    },
  );

  /// Figma «Frame 1/2»: filters, cards, add field under the header.
  Widget workspace(bool desktop, bool inline) {
    final active = c.tasks
            .where((t) => !t.completed || settling.contains(t.id))
            .toList(),
        completed = c.tasks
            .where((t) => t.completed && !settling.contains(t.id))
            .toList();
    final side = desktop ? 40.0 : 20.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        side,
        desktop ? 16 : 24,
        side,
        desktop ? 28 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          reflow(
            searching
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: searchField(),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Row(
            children: [
              desktop
                  ? Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 420,
                                ),
                                child: filters(),
                              ),
                            ),
                          ),
                          DayButton.icon(
                            tooltip: _mac ? 'Поиск · ⌘F' : 'Поиск · Ctrl+F',
                            sound: UiSound.open,
                            onPressed: searching ? closeSearch : openSearch,
                            icon: DayIcon(
                              searching ? DayGlyph.close : DayGlyph.search,
                              size: 18,
                              color: DayColors.of(context).text,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Expanded(child: filters()),
              if (c.reminderFailures.isNotEmpty) ...[
                const SizedBox(width: 12),
                Flexible(child: reminderWarning()),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: AnimatedSwitcher(
              duration: MotionTokens.duration(context, MotionTokens.reflow),
              switchInCurve: MotionTokens.easeOut,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, .02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(
                  '${c.query.view}-${c.query.listId}-$showCompleted',
                ),
                child: taskList(active, completed, desktop, inline),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TaskComposer(
            focusNode: composer,
            onAdd: (text) async {
              setState(() => showCompleted = false);
              await c.addTask(text);
            },
          ),
        ],
      ),
    );
  }

  Widget filters() => DaySegments(
    index: showCompleted ? 1 : 0,
    labels: const ['Активные', 'Выполненные'],
    onChanged: (i) => setState(() => showCompleted = i == 1),
  );

  /// The quiet states are not shown; only offline, sign-in and conflict
  /// messages surface, since they need the user.
  bool get syncAlert => !const {
    'Сохранено на устройстве',
    'Всё синхронизировано',
    'Синхронизация…',
  }.contains(widget.syncLabel);

  Widget syncStatus() {
    final colors = DayColors.of(context);
    return FluidSurface(
      enabled: widget.onSync != null,
      child: InkWell(
        onTap: widget.onSync,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              DayIcon(DayGlyph.cloud, size: 15, color: colors.icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.syncLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall!
                      .copyWith(color: colors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Figma screens are white panels with radius 28 on the canvas.
  Widget panel({required Widget child, Key? key}) {
    final colors = DayColors.of(context);
    return Container(
      key: key,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.screen,
        borderRadius: BorderRadius.circular(28),
      ),
      child: child,
    );
  }

  /// What the open view holds, so «Сегодня» and «Все задачи» explain
  /// themselves.
  String viewHint() {
    final open = c.tasks.where((t) => !t.completed).length;
    final count = '$open ${_plural(open, 'задача', 'задачи', 'задач')}';
    return switch (c.query.view) {
      TaskView.today => dateLabel(),
      TaskView.all => 'Все незавершённые, с любым сроком · $count',
      TaskView.list when c.query.listId == inboxId =>
        'Задачи без списка · $count',
      TaskView.list => count,
    };
  }

  String dateLabel() {
    final d = c.query.today.utc;
    final weekday = _weekdays[d.weekday - 1];
    return '${weekday[0].toUpperCase()}${weekday.substring(1)}, '
        '${d.day} ${_months[d.month - 1]}';
  }

  /// The phone header's top row: lists on the left, more on the right.
  Widget phoneBar({bool onField = false}) {
    final colors = DayColors.of(context);
    final ink = onField ? const Color(0xff141414) : colors.text;
    // 48px touch targets; the icons are shifted out so they still line up
    // with the title card edge.
    return SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Transform.translate(
            offset: const Offset(-11, 0),
            child: FluidSurface(
              sound: UiSound.open,
              pressScale: .9,
              child: Tooltip(
                message: 'Списки',
                child: InkResponse(
                  onTap: () => scaffold.currentState!.openDrawer(),
                  radius: 24,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: DayIcon(DayGlyph.hamburger, size: 26, color: ink),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(11, 0),
            child: PopupMenuButton<String>(
              tooltip: 'Ещё',
              position: PopupMenuPosition.under,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 180),
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
              ),
              onOpened: () => DaySound.play(context, UiSound.tap),
              icon: DayIcon(DayGlyph.more, size: 26, color: ink),
              onSelected: (action) => switch (action) {
                'search' => openSearch(),
                'settings' => widget.onSettings?.call(),
                _ => widget.onSync?.call(),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'search', child: Text('Поиск')),
                if (widget.onSettings != null)
                  const PopupMenuItem(
                    value: 'settings',
                    child: Text('Настройки'),
                  ),
                if (syncAlert)
                  PopupMenuItem(
                    value: 'sync',
                    enabled: widget.onSync != null,
                    child: Text(widget.syncLabel),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => CallbackShortcuts(
      bindings: {
        // ⌘ on macOS, Ctrl elsewhere.
        SingleActivator(
          LogicalKeyboardKey.keyN,
          control: !_mac,
          meta: _mac,
        ): () {
          setState(() => showCompleted = false);
          composer.requestFocus();
        },
        SingleActivator(LogicalKeyboardKey.keyF, control: !_mac, meta: _mac):
            openSearch,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (c.selectedId != null) DaySound.play(context, UiSound.close);
          c.select(null);
          if (searching) closeSearch();
          FocusScope.of(context).unfocus();
        },
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 900,
                inline = constraints.maxWidth >= 1280;
            final selected = inline ? c.selected : null;
            final colors = DayColors.of(context);
            final head = ScreenHeader(
              now: c.clock(),
              title: c.heading,
              subtitle: viewHint(),
              phone: !desktop,
              top: desktop ? null : phoneBar(onField: true),
            );
            final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
            return Scaffold(
              key: scaffold,
              backgroundColor: desktop ? colors.canvas : colors.screen,
              drawer: desktop
                  ? null
                  : Drawer(
                      width: 300,
                      backgroundColor: colors.screen,
                      child: ListPanel(
                        controller: c,
                        onNavigate: () => Navigator.pop(context),
                        onSettings: widget.onSettings,
                        status: syncAlert ? syncStatus() : null,
                      ),
                    ),
              body: desktop
                  ? SafeArea(
                      child: _MacTitleBar(
                        child: Padding(
                          // macOS: room for the traffic lights over the canvas.
                          padding: EdgeInsets.fromLTRB(
                            20,
                            _mac ? 34 : 20,
                            20,
                            20,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              panel(
                                key: const Key('desktop-sidebar'),
                                child: SizedBox(
                                  width: sidebarWidth,
                                  child: ListPanel(
                                    controller: c,
                                    onSettings: widget.onSettings,
                                    status: syncAlert ? syncStatus() : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: panel(
                                  // Figma: a 4px screen-coloured frame keeps
                                  // the gradient off the panel's edge.
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (!keyboard)
                                          ClipRRect(
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(24),
                                                ),
                                            child: head,
                                          ),
                                        Expanded(
                                          child: workspace(desktop, inline),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _DetailSlot(
                                child: selected == null
                                    ? null
                                    : Padding(
                                        // One key for the open panel: switching
                                        // tasks swaps content, not the panel.
                                        key: const ValueKey('detail'),
                                        padding: const EdgeInsets.only(
                                          left: 20,
                                        ),
                                        child: panel(
                                          child: SizedBox(
                                            width: 360,
                                            child: ChromaSwap(
                                              swapKey: selected.id,
                                              colors: [
                                                head.palette.stops[2],
                                                head.palette.stops[1],
                                                head.palette.stops[0],
                                              ],
                                              child: TaskDetailPanel(
                                                key: ValueKey(selected.id),
                                                task: selected,
                                                controller: c,
                                                onRequestReminder:
                                                    widget.onRequestReminder,
                                                onClose: () {
                                                  DaySound.play(
                                                    context,
                                                    UiSound.close,
                                                  );
                                                  c.select(null);
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (keyboard)
                          SafeArea(bottom: false, child: phoneBarPadded())
                        else
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              4,
                              4 + MediaQuery.paddingOf(context).top,
                              4,
                              0,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: MediaQuery.removePadding(
                                context: context,
                                removeTop: true,
                                child: head,
                              ),
                            ),
                          ),
                        Expanded(
                          child: SafeArea(
                            top: false,
                            child: workspace(desktop, inline),
                          ),
                        ),
                      ],
                    ),
            );
          },
        ),
      ),
    ),
  );

  Widget phoneBarPadded() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: phoneBar(),
  );
}

/// macOS: the window has no title bar of its own, so the strip above the
/// panels moves the window and a double click zooms it, like a real bar.
class _MacTitleBar extends StatelessWidget {
  final Widget child;
  const _MacTitleBar({required this.child});
  static const _channel = MethodChannel('day/platform');
  @override
  Widget build(BuildContext context) => !_mac
      ? child
      : Stack(
          children: [
            child,
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 30,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => _channel.invokeMethod('dragWindow'),
                onDoubleTap: () => _channel.invokeMethod('zoomWindow'),
              ),
            ),
          ],
        );
}

/// Detail card slides in from the right edge and folds the space it took.
class _DetailSlot extends StatelessWidget {
  final Widget? child;
  const _DetailSlot({this.child});
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MotionTokens.duration(context, MotionTokens.panel),
    reverseDuration: MotionTokens.duration(context, MotionTokens.panel),
    switchInCurve: MotionTokens.easeOut,
    switchOutCurve: MotionTokens.easeOut,
    transitionBuilder: (child, animation) => SizeTransition(
      sizeFactor: animation,
      axis: Axis.horizontal,
      alignment: Alignment.centerLeft,
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(.08, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
    ),
    // The outgoing panel stays in the row while it folds away, so closing
    // is as smooth as opening.
    layoutBuilder: (current, previous) => Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [...previous, ?current],
    ),
    child: child ?? const SizedBox.shrink(key: ValueKey('empty')),
  );
}

/// New rows fade in and rise a few pixels; existing rows never replay it.
class _Appear extends StatefulWidget {
  final bool animate;
  final Widget child;
  const _Appear({required this.animate, required this.child});
  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  late final curve = CurvedAnimation(
    parent: controller,
    curve: MotionTokens.easeOut,
  );
  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !MediaQuery.disableAnimationsOf(context)) {
          controller.forward(from: 0);
        }
      });
    }
  }

  @override
  void dispose() {
    curve.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: curve,
    child: widget.child,
    builder: (context, child) {
      final t = curve.value;
      if (t == 1) return child!;
      return ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: t,
          child: Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, -8 * (1 - t)),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

class _CardDrag extends ReorderableDragStartListener {
  const _CardDrag({required super.index, required super.child, super.enabled});
  @override
  MultiDragGestureRecognizer createRecognizer() =>
      VerticalMultiDragGestureRecognizer(debugOwner: this);
}

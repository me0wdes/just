import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models.dart';
import '../../platform/feedback_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/sync_status_icon.dart';
import '../../theme/chroma_swap.dart';
import '../../theme/controls.dart';
import '../../theme/day_icon.dart';
import '../../theme/day_sound.dart';
import '../../theme/fluid_surface.dart';
import '../../theme/motion_tokens.dart';
import '../../theme/segments.dart';
import 'list_panel.dart';
import 'task_composer.dart';
import 'task_controller.dart';
import 'task_detail_panel.dart';
import 'task_row.dart';
import 'week_header.dart';
import '../../theme/toast.dart';

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
  final composer = FocusNode();
  final scaffold = GlobalKey<ScaffoldState>();
  final scroll = ScrollController();
  bool showCompleted = false;
  final settling = <String>{}, collapsing = <String>{};

  /// Rows present at first paint stay still; rows added later rise in.
  final known = <String>{};
  bool primed = false;
  final motionTimers = <Timer>[];

  /// Where a touch began on a card and how far it has moved, to tell a long
  /// press (menu) from a drag (reorder).
  Offset? pressAt;
  double pressMoved = 0;
  void Function(Offset)? pressMenu;
  bool desktopLayout = true;
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
      c.navigate(TaskView.all);
      await open(task, MediaQuery.sizeOf(context).width >= 1280);
    });
  }

  @override
  void dispose() {
    c.removeListener(_openRequestedTask);
    composer.dispose();
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
        DayToast.show(
          context,
          '«${task.title}» выполнена',
          action: 'Вернуть',
          onAction: () async {
            final saved = await c.repository.readTask(task.id);
            if (saved?.completionId != null) {
              await c.undoCompletion(task.id, saved!.completionId!);
            }
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          settling.remove(task.id);
          collapsing.remove(task.id);
        });
        DaySound.play(context, UiSound.error);
        DayToast.show(context, 'Не удалось изменить задачу');
      }
    }
  }

  Future<void> remove(TaskItem task) async {
    DaySound.play(context, UiSound.delete);
    if (c.selectedId == task.id) c.select(null);
    await c.deleteTask(task.id);
    if (!mounted) return;
    DayToast.show(
      context,
      'Задача удалена',
      action: 'Отменить',
      onAction: () => c.restoreTask(task.id),
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
        // The panel paints its own square background; clip it to the corners.
        clipBehavior: Clip.antiAlias,
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
                  completedTab ? DayGlyph.check : DayGlyph.sun,
                  size: 26,
                  color: colors.muted,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                completedTab ? 'Пока ничего не выполнено' : 'Здесь пока тихо',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                completedTab
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
      // Touch: a long press that never moved opens the card's menu, the way
      // a right click does on a computer; a moved one reorders.
      onReorderEnd: (_) {
        final at = pressAt, menu = pressMenu;
        if (!desktopLayout && at != null && menu != null && pressMoved < 12) {
          HapticFeedback.selectionClick();
          menu(at);
        }
        pressAt = null;
      },
      onReorderItem: (oldIndex, newIndex) {
        if (!desktopLayout && pressMoved < 12) return;
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
          // A finished card cannot be dragged, so its long press is free.
          longPressMenu: !desktop && task.completed,
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
                          : Listener(
                              onPointerDown: (e) {
                                pressAt = e.position;
                                pressMoved = 0;
                                pressMenu = row.onMenu;
                              },
                              onPointerMove: (e) {
                                final start = pressAt;
                                if (start == null) return;
                                final d = (e.position - start).distance;
                                if (d > pressMoved) pressMoved = d;
                              },
                              child: ReorderableDelayedDragStartListener(
                                index: index,
                                enabled: !task.completed,
                                child: row,
                              ),
                            ),
                    ),
                  ),
          ),
        );
      },
    );
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
        builder: (context) => DayDialog(
          width: 460,
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
            DayButton(
              kind: DayButtonKind.primary,
              onPressed: () => Navigator.pop(context),
              label: const Text('Понятно'),
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
  /// Connected to a server: the lists panel always shows how sync is doing.
  bool get connected => widget.syncLabel != 'Сохранено на устройстве';

  bool get syncAlert => !const {
    'Сохранено на устройстве',
    'Всё синхронизировано',
    'Синхронизация…',
  }.contains(widget.syncLabel);

  /// Figma «Синхронизация · значок»: the cloud with its status, 40 px,
  /// beside «Настройки»; the hint says what a tap does.
  Widget syncStatus() {
    final colors = DayColors.of(context);
    final mark = switch (widget.syncLabel) {
      'Всё синхронизировано' => SyncMark.done,
      'Синхронизация…' => SyncMark.busy,
      _ => SyncMark.error,
    };
    final hint = switch (mark) {
      SyncMark.done => '${widget.syncLabel} · нажмите, чтобы обновить',
      SyncMark.busy => widget.syncLabel,
      SyncMark.error => '${widget.syncLabel} · нажмите, чтобы повторить',
    };
    return Tooltip(
      message: hint,
      child: Semantics(
        button: true,
        label: hint,
        excludeSemantics: true,
        child: FluidSurface(
          enabled: widget.onSync != null,
          pressScale: .92,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: const Key('sidebar-sync'),
              onTap: widget.onSync,
              borderRadius: BorderRadius.circular(8),
              hoverColor: colors.hover,
              child: SizedBox.square(
                dimension: 40,
                child: Center(child: SyncCloud(mark, cutout: colors.screen)),
              ),
            ),
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

  /// The phone header's top row: lists on the left, more on the right.
  Widget phoneBar({bool onField = false}) {
    final colors = DayColors.of(context);
    // 48px touch targets; the icons are shifted out so they still line up
    // with the title card edge.
    // Figma «Шапка»: only the lists button; settings and sync live in the
    // drawer it opens.
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Transform.translate(
            offset: const Offset(-2, 0),
            child: FluidSurface(
              sound: UiSound.open,
              pressScale: .9,
              // Figma «menu icon»: a 44 px circle in the screen colour.
              child: Tooltip(
                message: 'Списки',
                child: InkResponse(
                  onTap: () => scaffold.currentState!.openDrawer(),
                  radius: 24,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.screen,
                          shape: BoxShape.circle,
                        ),
                        child: DayIcon(
                          DayGlyph.hamburger,
                          size: 20,
                          color: colors.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Sync needs a look (syncing, offline, key lost): a cloud on the
          // right says so without opening the drawer.
          if (connected && widget.syncLabel != 'Всё синхронизировано') ...[
            const Spacer(),
            Transform.translate(
              offset: const Offset(2, 0),
              child: FluidSurface(
                pressScale: .9,
                enabled: widget.onSync != null,
                child: Tooltip(
                  message: widget.syncLabel,
                  child: Semantics(
                    button: true,
                    label: widget.syncLabel,
                    child: InkResponse(
                      key: const Key('phone-sync'),
                      onTap: widget.onSync,
                      radius: 24,
                      child: SizedBox.square(
                        dimension: 48,
                        child: Center(
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.screen,
                              shape: BoxShape.circle,
                            ),
                            child: DayIcon(
                              DayGlyph.cloud,
                              size: 20,
                              color: syncAlert ? colors.overdue : colors.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (c.selectedId != null) DaySound.play(context, UiSound.close);
          c.select(null);
          FocusScope.of(context).unfocus();
        },
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 900,
                inline = constraints.maxWidth >= 1280;
            desktopLayout = desktop;
            final selected = inline ? c.selected : null;
            final colors = DayColors.of(context);
            final head = WeekHeader(
              controller: c,
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
                        status: connected ? syncStatus() : null,
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
                                    status: connected ? syncStatus() : null,
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
                                              // Quiet grey haze in the panel's own tone.
                                              colors: [
                                                for (final k in const [
                                                  .07,
                                                  .12,
                                                  .03,
                                                ])
                                                  Color.lerp(
                                                    DayColors.of(context)
                                                        .screen,
                                                    DayColors.of(context).text,
                                                    k,
                                                  )!,
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
                          // Figma «Новые секции · телефон»: the field runs
                          // under the status bar, edge to edge, and rounds
                          // only its bottom (40).
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(40),
                            ),
                            child: head,
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

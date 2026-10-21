import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../platform/feedback_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/day_icon.dart';
import '../../theme/controls.dart';
import '../../theme/day_sound.dart';
import '../../theme/fluid_button.dart';
import '../../theme/fluid_surface.dart';
import '../../theme/motion_tokens.dart';
import 'task_controller.dart';

/// Sidebar card: views, personal lists and settings. The selection pill
/// slides between rows instead of jumping.
class ListPanel extends StatelessWidget {
  final TaskController controller;
  final VoidCallback? onNavigate, onSettings;
  final bool brand;
  const ListPanel({
    super.key,
    required this.controller,
    this.onNavigate,
    this.onSettings,
    this.brand = true,
    this.status,
  });

  /// Sync status shown quietly above settings.
  final Widget? status;
  Future<void> edit(BuildContext context, {TaskList? list}) async {
    final text = TextEditingController(text: list?.name);
    DaySound.play(context, UiSound.open);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(list == null ? 'Новый список' : 'Название списка'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: text,
            autofocus: true,
            maxLength: 500,
            decoration: const InputDecoration(hintText: 'Например, Дом'),
            onSubmitted: (s) => Navigator.pop(context, s),
          ),
        ),
        actions: [
          FluidButton.text(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FluidButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    text.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await controller.saveList(list?.id, name);
      if (context.mounted) {
        DaySound.play(context, list == null ? UiSound.add : UiSound.tap);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final theme = Theme.of(context);
    final extent = MediaQuery.textScalerOf(context).scale(15) + 25;
    const gap = 4.0;
    final q = controller.query;
    final rows = <Widget>[];
    double y = 0, selectedTop = -1;
    void item(
      String title,
      DayGlyph icon,
      bool selected,
      VoidCallback tap, {
      void Function(Offset at)? onMenu,
    }) {
      if (selected) selectedTop = y;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: gap),
          child: _NavItem(
            title: title,
            icon: icon,
            selected: selected,
            height: extent,
            onMenu: onMenu,
            onTap: () {
              tap();
              onNavigate?.call();
            },
          ),
        ),
      );
      y += extent + gap;
    }

    void label(String text) {
      final height = MediaQuery.textScalerOf(context).scale(13) + 22;
      rows.add(
        SizedBox(
          height: height,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Text(
                text,
                style: theme.textTheme.bodySmall!.copyWith(color: c.muted),
              ),
            ),
          ),
        ),
      );
      y += height;
    }

    item(
      'Сегодня',
      DayGlyph.sun,
      q.view == TaskView.today,
      () => controller.navigate(TaskView.today),
    );
    item(
      'Все задачи',
      DayGlyph.tasks,
      q.view == TaskView.all,
      () => controller.navigate(TaskView.all),
    );
    label('Мои списки');
    for (final list in controller.lists) {
      item(
        TaskController.listTitle(list),
        list.id == inboxId ? DayGlyph.note : DayGlyph.list,
        q.view == TaskView.list && q.listId == list.id,
        () => controller.navigate(TaskView.list, listId: list.id),
        // Right click (long press on touch) instead of a «…» button.
        onMenu: list.id == inboxId
            ? null
            : (at) => showDayMenu(context, at, [
                DayMenuItem(
                  'Переименовать',
                  DayGlyph.note,
                  () => edit(context, list: list),
                ),
                DayMenuItem('Удалить список', DayGlyph.delete, () {
                  DaySound.play(context, UiSound.delete);
                  controller.deleteList(list.id);
                }, destructive: true),
              ]),
      );
    }
    rows.add(
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: _NavItem(
          title: 'Новый список',
          icon: DayGlyph.add,
          selected: false,
          height: extent,
          sound: null,
          onTap: () => edit(context),
        ),
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (brand)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Text(
                  'Just',
                  style: theme.textTheme.headlineMedium!.copyWith(
                    color: c.text,
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                child: Stack(
                  children: [
                    if (selectedTop >= 0)
                      AnimatedPositioned(
                        duration: MotionTokens.duration(
                          context,
                          const Duration(milliseconds: 280),
                        ),
                        curve: const Cubic(.2, 1.1, .3, 1),
                        top: selectedTop,
                        left: 0,
                        right: 0,
                        height: extent,
                        child: DecoratedBox(
                          key: const Key('sidebar-selection'),
                          decoration: BoxDecoration(
                            color: c.selected,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: rows,
                    ),
                  ],
                ),
              ),
            ),
            if (status != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: status!,
              ),
            if (onSettings != null) ...[
              _NavItem(
                title: 'Настройки',
                icon: DayGlyph.settings,
                selected: false,
                height: extent,
                sound: null,
                onTap: onSettings!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final String title;
  final DayGlyph icon;
  final bool selected;
  final double height;
  final VoidCallback onTap;
  final void Function(Offset at)? onMenu;
  final UiSound? sound;
  const _NavItem({
    required this.title,
    required this.icon,
    required this.selected,
    required this.height,
    required this.onTap,
    this.onMenu,
    this.sound = UiSound.nav,
  });
  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final fg = widget.selected || hovered ? c.text : c.muted;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: FluidSurface(
        pressScale: .985,
        sound: widget.selected ? null : widget.sound,
        child: Semantics(
          selected: widget.selected,
          button: true,
          child: Material(
            color: !widget.selected && hovered ? c.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: widget.onTap,
              onSecondaryTapUp: widget.onMenu == null
                  ? null
                  : (d) => widget.onMenu!(d.globalPosition),
              onLongPress: widget.onMenu == null
                  ? null
                  : () {
                      final box = context.findRenderObject() as RenderBox;
                      widget.onMenu!(
                        box.localToGlobal(box.size.centerLeft(Offset.zero)),
                      );
                    },
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: widget.height,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    DayIcon(widget.icon, size: 20, color: fg),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: fg,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

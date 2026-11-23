import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../platform/feedback_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/day_icon.dart';
import '../../theme/day_sheet.dart';
import '../../theme/controls.dart';
import '../../theme/day_sound.dart';
import '../../theme/fluid_button.dart';
import '../../theme/fluid_surface.dart';
import '../../theme/motion_tokens.dart';
import 'task_controller.dart';
import 'task_row.dart' show listColor;

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

  /// Sync status as an icon beside settings.
  final Widget? status;
  Future<void> edit(BuildContext context, {TaskList? list}) async {
    DaySound.play(context, UiSound.open);
    final result = await showDayPanel<(String, String, String)>(
      context,
      (_) => _ListDialog(list: list, fresh: controller.nextListColor),
    );
    if (result == null || result.$1.trim().isEmpty) return;
    await controller.saveList(
      list?.id,
      result.$1,
      icon: result.$2,
      color: result.$3,
    );
    if (context.mounted) {
      DaySound.play(context, list == null ? UiSound.add : UiSound.tap);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final theme = Theme.of(context);
    // Phone rows are 48 tall for a finger; a computer keeps 40.
    final extent =
        MediaQuery.textScalerOf(context).scale(15) +
        (MediaQuery.sizeOf(context).width < 600 ? 33 : 25);
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
      Color? tint,
    }) {
      if (selected) selectedTop = y;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: gap),
          child: _NavItem(
            title: title,
            icon: icon,
            tint: tint,
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
      'Предстоящие',
      DayGlyph.deadline,
      q.view == TaskView.all,
      () => controller.navigate(TaskView.all),
    );
    label('Мои списки');
    // Tasks without a list live in «Предстоящие»; the inbox has no entry.
    for (final list in controller.lists.where((l) => l.id != inboxId)) {
      item(
        list.name,
        listGlyph(list.icon),
        q.view == TaskView.list && q.listId == list.id,
        () => controller.navigate(TaskView.list, listId: list.id),
        tint: listColor(list),
        // Right click (long press on touch) instead of a «…» button.
        onMenu: (at) => showDayMenu(context, at, [
          DayMenuItem(
            'Изменить',
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
            if (onSettings != null)
              // Figma «Низ»: settings, and the sync cloud beside it while a
              // server is connected.
              Row(
                children: [
                  Expanded(
                    child: _NavItem(
                      title: 'Настройки',
                      icon: DayGlyph.settings,
                      selected: false,
                      height: extent,
                      sound: null,
                      onTap: onSettings!,
                    ),
                  ),
                  if (status != null) ...[const SizedBox(width: 4), status!],
                ],
              )
            else if (status != null)
              Align(alignment: Alignment.centerRight, child: status!),
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

  /// A list's own colour for its icon; null keeps the menu's grey/white.
  final Color? tint;
  const _NavItem({
    required this.title,
    required this.icon,
    this.tint,
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
                    DayIcon(widget.icon, size: 20, color: widget.tint ?? fg),
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

/// «Новый список» / «Список»: name and icon together, as in Figma.
class _ListDialog extends StatefulWidget {
  final TaskList? list;

  /// The colour a new list starts with.
  final String fresh;
  const _ListDialog({this.list, required this.fresh});
  @override
  State<_ListDialog> createState() => _ListDialogState();
}

class _ListDialogState extends State<_ListDialog> {
  late final name = TextEditingController(text: widget.list?.name);
  late String icon = widget.list?.icon ?? 'stack';
  late String color = (widget.list?.tint ?? widget.fresh).toUpperCase();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void submit() => Navigator.pop(context, (name.text, icon, color));

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final theme = Theme.of(context);
    return DayPanel(
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.list == null ? 'Новый список' : 'Список',
                style: theme.textTheme.titleMedium!.copyWith(color: c.text),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                autofocus: true,
                maxLength: 500,
                onSubmitted: (_) => submit(),
                decoration: const InputDecoration(
                  hintText: 'Например, Покупки',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Иконка',
                style: theme.textTheme.bodySmall!.copyWith(color: c.muted),
              ),
              const SizedBox(height: 8),
              DayIconGrid(
                selected: icon,
                onPick: (key) => setState(() => icon = key),
              ),
              const SizedBox(height: 16),
              Text(
                'Цвет',
                style: theme.textTheme.bodySmall!.copyWith(color: c.muted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final hex in listPalette)
                    _ColorDot(
                      hex: hex,
                      selected: hex == color,
                      onTap: () => setState(() => color = hex),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FluidButton.text(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  FluidButton(
                    onPressed: submit,
                    child: Text(widget.list == null ? 'Создать' : 'Сохранить'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One colour of the list dialog: a dot, ringed when it is the one chosen.
class _ColorDot extends StatelessWidget {
  final String hex;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot({
    required this.hex,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final color = Color(0xff000000 | int.parse(hex.substring(1), radix: 16));
    return Semantics(
      button: true,
      selected: selected,
      label: 'Цвет $hex',
      child: FluidSurface(
        pressScale: .9,
        child: GestureDetector(
          key: ValueKey('list-color-$hex'),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? color : Colors.transparent,
                width: 2,
              ),
            ),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'fluid_surface.dart';

enum DayGlyph {
  sun,
  tasks,
  inbox,
  list,
  settings,
  search,
  check,
  repeat,
  bell,
  note,
  close,
  deadline,
  delete,
  add,
  send,
  cloud,
  down,
  up,
  more,
  grip,
  menu,
  upload,
  download,
  warning,
  clock,
  hamburger,
}

class DayIcon extends StatelessWidget {
  final DayGlyph glyph;
  final double? size;
  final Color? color;
  const DayIcon(this.glyph, {super.key, this.size, this.color});
  static const _assets = {
    DayGlyph.sun: 'brightness-down-icon',
    DayGlyph.tasks: 'unordered-list-icon',
    DayGlyph.inbox: 'download-icon',
    DayGlyph.list: 'stack-3-icon',
    DayGlyph.settings: 'gear-icon',
    DayGlyph.search: 'magnifier-icon',
    DayGlyph.check: 'simple-checked-icon',
    DayGlyph.repeat: 'refresh-icon',
    DayGlyph.bell: 'filled-bell-icon',
    DayGlyph.note: 'file-description-icon',
    DayGlyph.close: 'x-icon',
    DayGlyph.deadline: 'alarm-clock-plus-icon',
    DayGlyph.delete: 'trash-icon',
    DayGlyph.add: 'x-icon',
    DayGlyph.send: 'arrow-narrow-up-icon',
    DayGlyph.cloud: 'cloud-1-icon',
    DayGlyph.down: 'down-chevron',
    DayGlyph.up: 'down-chevron',
    DayGlyph.more: 'dots-horizontal-icon',
    DayGlyph.grip: 'dots-vertical-icon',
    DayGlyph.menu: 'layout-sidebar-right-collapse-icon',
    DayGlyph.upload: 'upload-icon',
    DayGlyph.download: 'download-icon',
    DayGlyph.warning: 'triangle-alert-icon',
    DayGlyph.clock: 'clock-icon',
    DayGlyph.hamburger: 'menu-icon',
  };
  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context),
        interaction = FluidInteraction.of(context);
    final t = MediaQuery.disableAnimationsOf(context)
        ? 0.0
        : math.max(interaction?.hover ?? 0, interaction?.press ?? 0);
    final rotation = switch (glyph) {
      DayGlyph.settings => t * math.pi / 6,
      DayGlyph.search => -.08 * math.sin(t * math.pi),
      DayGlyph.bell => .12 * math.sin(t * math.pi * 2),
      DayGlyph.sun => t * .15,
      _ => 0.0,
    };
    final offset = switch (glyph) {
      DayGlyph.send => Offset(0, -1.5 * t),
      DayGlyph.upload => Offset(0, -t),
      DayGlyph.download => Offset(0, t),
      DayGlyph.list => Offset(0, -.8 * t),
      _ => Offset.zero,
    };
    final baseRotation = glyph == DayGlyph.add
        ? math.pi / 4
        : glyph == DayGlyph.up
        ? math.pi
        : 0.0;
    final dimension = size ?? theme.size ?? 24;
    return ExcludeSemantics(
      child: Transform.translate(
        offset: offset,
        child: Transform.rotate(
          angle: baseRotation + rotation,
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: SvgPicture.asset(
              'assets/icons/itshover/${_assets[glyph]}.svg',
              width: dimension,
              height: dimension,
              colorFilter: ColorFilter.mode(
                color ?? theme.color ?? Theme.of(context).colorScheme.onSurface,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

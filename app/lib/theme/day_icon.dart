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
  listStack,
  listHome,
  listWork,
  listCart,
  listBook,
  listIdeas,
  listHeart,
  listGoals,
  listTravel,
  listGlobe,
  listCode,
  listCamera,
  listCoffee,
  listWallet,
  listGame,
  listPets,
  listRocket,
  listPeople,
}

/// List icon keys as stored in `TaskList.icon`, in picker order.
const listIconKeys = [
  'stack',
  'home',
  'work',
  'cart',
  'book',
  'ideas',
  'heart',
  'goals',
  'travel',
  'globe',
  'code',
  'camera',
  'coffee',
  'wallet',
  'game',
  'pets',
  'rocket',
  'people',
];

DayGlyph listGlyph(String key) =>
    DayGlyph.values
        .asNameMap()['list${key.isEmpty ? '' : key[0].toUpperCase()}${key.length > 1 ? key.substring(1) : ''}'] ??
    DayGlyph.listStack;

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
    DayGlyph.listStack: 'list-stack',
    DayGlyph.listHome: 'list-home',
    DayGlyph.listWork: 'list-work',
    DayGlyph.listCart: 'list-cart',
    DayGlyph.listBook: 'list-book',
    DayGlyph.listIdeas: 'list-ideas',
    DayGlyph.listHeart: 'list-heart',
    DayGlyph.listGoals: 'list-goals',
    DayGlyph.listTravel: 'list-travel',
    DayGlyph.listGlobe: 'list-globe',
    DayGlyph.listCode: 'list-code',
    DayGlyph.listCamera: 'list-camera',
    DayGlyph.listCoffee: 'list-coffee',
    DayGlyph.listWallet: 'list-wallet',
    DayGlyph.listGame: 'list-game',
    DayGlyph.listPets: 'list-pets',
    DayGlyph.listRocket: 'list-rocket',
    DayGlyph.listPeople: 'list-people',
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
      // List icons: small ItsHover-style gestures on hover.
      DayGlyph.listIdeas || DayGlyph.listGlobe => t * .26,
      DayGlyph.listBook || DayGlyph.listWork => -.12 * math.sin(t * math.pi),
      DayGlyph.listGame || DayGlyph.listPets => .14 * math.sin(t * math.pi * 2),
      _ => 0.0,
    };
    final offset = switch (glyph) {
      DayGlyph.send => Offset(0, -1.5 * t),
      DayGlyph.upload => Offset(0, -t),
      DayGlyph.download => Offset(0, t),
      DayGlyph.list => Offset(0, -.8 * t),
      DayGlyph.listStack ||
      DayGlyph.listHome ||
      DayGlyph.listGoals ||
      DayGlyph.listCoffee => Offset(0, -1.5 * t),
      DayGlyph.listCart || DayGlyph.listWallet => Offset(1.5 * t, 0),
      DayGlyph.listTravel || DayGlyph.listRocket => Offset(1.5 * t, -1.5 * t),
      _ => Offset.zero,
    };
    final scale = switch (glyph) {
      DayGlyph.listHeart ||
      DayGlyph.listCamera ||
      DayGlyph.listCode ||
      DayGlyph.listPeople => 1 + .12 * math.sin(t * math.pi),
      _ => 1.0,
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
          child: Transform.scale(
            scale: scale,
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: SvgPicture.asset(
                'assets/icons/itshover/${_assets[glyph]}.svg',
                width: dimension,
                height: dimension,
                colorFilter: ColorFilter.mode(
                  color ??
                      theme.color ??
                      Theme.of(context).colorScheme.onSurface,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

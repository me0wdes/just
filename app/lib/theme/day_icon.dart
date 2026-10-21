import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_parsing/path_parsing.dart';

import 'fluid_surface.dart';

part 'icon_motion.g.dart';

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

/// ItsHover icons with their own motion, baked frame by frame from the React
/// components by `tools/bake-icons`. The motion plays while the surrounding
/// [FluidSurface] is hovered or pressed and settles back when it is released.
class DayIcon extends StatefulWidget {
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
  State<DayIcon> createState() => _DayIconState();
}

class _DayIconState extends State<DayIcon> with SingleTickerProviderStateMixin {
  static const _fps = 30.0, _blend = .12;
  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier(0);
  _Phase _phase = _Phase.rest;
  Duration _phaseStart = Duration.zero, _now = Duration.zero;
  List<List<double>>? _from;

  _IconMotion get _motion => _baked[DayIcon._assets[widget.glyph]]!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final interaction = FluidInteraction.of(context);
    final active =
        !MediaQuery.disableAnimationsOf(context) &&
        math.max(interaction?.hover ?? 0, interaction?.press ?? 0) > .5;
    if (active && _phase != _Phase.start) {
      _enter(_Phase.start);
    } else if (!active && _phase == _Phase.start) {
      _enter(_Phase.stop);
    }
  }

  @override
  void didUpdateWidget(DayIcon old) {
    super.didUpdateWidget(old);
    if (old.glyph != widget.glyph) {
      _phase = _Phase.rest;
      _from = null;
      _ticker.stop();
    }
  }

  void _enter(_Phase phase) {
    // Motion picks up from wherever the previous phase left the parts.
    _from = _phase == _Phase.rest ? null : _values();
    _phase = phase;
    _phaseStart = _now;
    if (!_ticker.isActive) {
      _now = _phaseStart = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration now) {
    _now = now;
    final m = _motion;
    if (_phase == _Phase.stop &&
        _elapsed * _fps >= math.max(m.stop - 1, 0) &&
        _elapsed >= _blend) {
      _phase = _Phase.rest;
      _from = null;
      _ticker.stop();
    }
    _frame.value++;
  }

  double get _elapsed => (_now - _phaseStart).inMicroseconds / 1e6;

  /// Frame position in the combined start + stop timeline, or null at rest.
  double? get _position {
    final m = _motion, f = _elapsed * _fps;
    switch (_phase) {
      case _Phase.rest:
        return null;
      case _Phase.start:
        if (m.start == 0) return null;
        final last = m.start - 1.0;
        if (m.loop > 0 && f > last) return last - m.loop + (f - last) % m.loop;
        return math.min(f, last);
      case _Phase.stop:
        if (m.stop == 0) return null;
        return m.start + math.min(f, m.stop - 1.0);
    }
  }

  List<List<double>> _values() {
    final m = _motion, at = _position;
    final values = [for (final p in m.parts) at == null ? p.rest : p.at(at)];
    final from = _from;
    if (from == null) return values;
    final t = Curves.easeOut.transform(math.min(_elapsed / _blend, 1));
    return [
      for (var i = 0; i < values.length; i++)
        [
          for (var c = 0; c < 9; c++)
            ui.lerpDouble(from[i][c], values[i][c], t)!,
        ],
    ];
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final dimension = widget.size ?? theme.size ?? 24;
    final color =
        widget.color ?? theme.color ?? Theme.of(context).colorScheme.onSurface;
    final turn = switch (widget.glyph) {
      DayGlyph.add => math.pi / 4,
      DayGlyph.up => math.pi,
      _ => 0.0,
    };
    return ExcludeSemantics(
      child: Transform.rotate(
        angle: turn,
        child: CustomPaint(
          size: Size.square(dimension),
          painter: _IconPainter(_motion, color, _values, _frame),
        ),
      ),
    );
  }
}

enum _Phase { rest, start, stop }

class _IconMotion {
  final List<double> box;
  final int start, stop, loop;
  final List<_Part> parts;
  const _IconMotion({
    required this.box,
    required this.start,
    required this.stop,
    required this.loop,
    required this.parts,
  });
}

/// One shape of an icon. [rest] and each frame hold the affine matrix
/// (a b c d e f), opacity and the drawn stretch of the stroke (start, end);
/// [frames] keep only the [channels] that move.
class _Part {
  final String d;
  final bool fill, stroke;
  final double width;
  final List<double> rest;
  final List<int> channels;
  final List<double> frames;
  const _Part(
    this.d, {
    required this.fill,
    required this.stroke,
    required this.width,
    required this.rest,
    this.channels = const [],
    this.frames = const [],
  });

  static final _paths = Expando<Path>();
  Path get path => _paths[this] ??= (() {
    final proxy = _PathProxy();
    writeSvgPathDataToPath(d, proxy);
    return proxy.path;
  })();

  List<double> at(double position) {
    if (channels.isEmpty) return rest;
    final n = channels.length, count = frames.length ~/ n;
    final i = position.floor().clamp(0, count - 1),
        j = math.min(i + 1, count - 1),
        t = position - position.floor();
    final out = [...rest];
    for (var k = 0; k < n; k++) {
      out[channels[k]] = ui.lerpDouble(
        frames[i * n + k],
        frames[j * n + k],
        t,
      )!;
    }
    return out;
  }
}

class _PathProxy extends PathProxy {
  final path = Path();
  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
  @override
  void lineTo(double x, double y) => path.lineTo(x, y);
  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);
  @override
  void close() => path.close();
}

class _IconPainter extends CustomPainter {
  final _IconMotion motion;
  final Color color;
  final List<List<double>> Function() values;
  _IconPainter(this.motion, this.color, this.values, Listenable frame)
    : super(repaint: frame);

  @override
  void paint(Canvas canvas, Size size) {
    final box = motion.box, scale = size.width / box[2];
    canvas.scale(scale);
    canvas.translate(-box[0], -box[1]);
    final all = values();
    for (var i = 0; i < motion.parts.length; i++) {
      final part = motion.parts[i], v = all[i];
      final opacity = v[6].clamp(0.0, 1.0);
      if (opacity < .005 || v[8] - v[7] < .001) continue;
      var path = part.path;
      if (v[7] > .001 || v[8] < .999) path = _trim(path, v[7], v[8]);
      canvas.save();
      canvas.transform(
        Float64List.fromList([
          v[0],
          v[1],
          0,
          0,
          v[2],
          v[3],
          0,
          0,
          0,
          0,
          1,
          0,
          v[4],
          v[5],
          0,
          1,
        ]),
      );
      final paint = Paint()
        ..isAntiAlias = true
        ..color = color.withValues(alpha: color.a * opacity);
      if (part.fill) canvas.drawPath(path, paint..style = PaintingStyle.fill);
      if (part.stroke) {
        canvas.drawPath(
          path,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = part.width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      canvas.restore();
    }
  }

  /// The stretch [from]..[to] of the whole path, as SVG pathLength draws it.
  static Path _trim(Path path, double from, double to) {
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold(0.0, (sum, m) => sum + m.length);
    final out = Path();
    var offset = 0.0;
    for (final m in metrics) {
      final a = (from * total - offset).clamp(0.0, m.length),
          b = (to * total - offset).clamp(0.0, m.length);
      if (b > a) out.addPath(m.extractPath(a, b), Offset.zero);
      offset += m.length;
    }
    return out;
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.motion != motion || old.color != color;
}

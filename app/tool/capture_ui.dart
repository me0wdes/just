import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:day_planner/app.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/platform/feedback_service.dart';
import 'package:day_planner/features/tasks/greeting_header.dart';
import 'package:day_planner/theme/app_theme.dart';

const home = '6f0c2a54-4b9e-4f6b-9a51-0d3c7e1a2b01',
    work = '6f0c2a54-4b9e-4f6b-9a51-0d3c7e1a2b02';

void main() {
  for (final (width, height) in [
    (375.0, 812.0),
    (1280.0, 800.0),
    (1440.0, 860.0),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('capture $width dark=$dark', (tester) async {
        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: true);
        await tester.runAsync(RoseGoldField.load);
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        final font = FontLoader('Golos')
          ..addFont(rootBundle.load('assets/fonts/GolosText.ttf'));
        await tester.runAsync(font.load);
        final serif = FontLoader('Instrument Serif')
          ..addFont(rootBundle.load('assets/fonts/InstrumentSerif-Regular.ttf'));
        await tester.runAsync(serif.load);
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await tester.runAsync(icons.load);
        final db = AppDatabase.memory(workspaceId: 'sample');
        final repo = SqliteTaskRepository(db);
        final today = LocalDate.parse('2026-10-19');
        await repo.execute(TaskCommand.createList(home, 'Дом', icon: 'home'));
        await repo.execute(TaskCommand.createList(work, 'Работа', icon: 'work'));
        final samples = [
          (
            'Разобрать заметки за неделю',
            inboxId,
            'Собрать идеи в один документ',
            '2026-10-19',
          ),
          ('Записаться к стоматологу', home, '', '2026-10-17'),
          (
            'Созвон по макетам Just',
            work,
            'Показать тёмную тему и звуки',
            '2026-10-20',
          ),
          ('Погулять без телефона', home, '', null),
          ('Выбрать книгу на вечер', inboxId, '', null),
        ];
        var position = 0;
        for (final (title, list, note, due) in samples) {
          final id = const Uuid().v4();
          await repo.execute(
            TaskCommand.createTask(
              id: id,
              title: title,
              listId: inboxId,
              fields: {
                if (list != inboxId) 'listIds': [list],
                'plannedForDate': today.toString(),
                'position': (position++) * 1024,
                if (note.isNotEmpty) 'note': note,
                'dueDate': ?due,
                if (title.startsWith('Созвон')) 'dueTime': '13:00',
              },
            ),
          );
        }
        await repo.execute(
          TaskCommand.createTask(
            id: const Uuid().v4(),
            title: 'Оплатить интернет',
            listId: inboxId,
            fields: {
              'listIds': [home],
              'plannedForDate': today.toString(),
              'position': 9000,
            },
          ),
        );
        final c = TaskController(
          repo,
          feedback: const SilentCompletionFeedback(),
          today: () => today,
          clock: () => DateTime(2026, 10, 19, 13),
        );
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: DayApp(
              controller: c,
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        final done = c.tasks.firstWhere((t) => t.title == 'Оплатить интернет');
        await c.completeTask(done.id);
        await tester.pumpAndSettle();
        if (width > 1300) {
          c.select(c.tasks.firstWhere((t) => t.title.startsWith('Созвон')).id);
          await tester.pumpAndSettle();
        }
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../.tools/ui-captures/ui-${width.toInt()}-${dark ? 'dark' : 'light'}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await db.close();
      });
    }
  }
  for (final hour in [9, 14, 22]) {
    for (final dark in [false, true]) {
      testWidgets('header $hour dark=$dark', (tester) async {
        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: true);
        await tester.runAsync(RoseGoldField.load);
        tester.view.physicalSize = const Size(375, 194);
        tester.view.devicePixelRatio = 1;
        final font = FontLoader('Golos')
          ..addFont(rootBundle.load('assets/fonts/GolosText.ttf'));
        await tester.runAsync(font.load);
        final serif = FontLoader('Instrument Serif')
          ..addFont(rootBundle.load('assets/fonts/InstrumentSerif-Regular.ttf'));
        await tester.runAsync(serif.load);
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dayTheme(dark ? Brightness.dark : Brightness.light),
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: ScreenHeader(
                  title: 'Сегодня',
                  subtitle: 'Понедельник, 19 октября',
                  phone: true,
                  now: DateTime(2026, 10, 19, hour),
                  top: const SizedBox(height: 28),
                ),
              ),
            ),
          ),
        );
        // Let the shader future land so the live field paints, not the fallback.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../.tools/ui-captures/header-$hour-${dark ? 'dark' : 'light'}.png',
          );
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}

import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/app_bar_focus_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

void main() {
  group('AppBarFocusRingPainter', () {
    test('shouldRepaint returns true when properties differ', () {
      const p1 = AppBarFocusRingPainter(
        isFocused: false,
        isHovered: false,
        isPressed: false,
        progress: 1.0,
      );
      const p2 = AppBarFocusRingPainter(
        isFocused: false,
        isHovered: false,
        isPressed: false,
        progress: 1.0,
      );
      const pFocused = AppBarFocusRingPainter(
        isFocused: true,
        isHovered: false,
        isPressed: false,
        progress: 1.0,
      );
      const pHovered = AppBarFocusRingPainter(
        isFocused: false,
        isHovered: true,
        isPressed: false,
        progress: 1.0,
      );
      const pPressed = AppBarFocusRingPainter(
        isFocused: false,
        isHovered: false,
        isPressed: true,
        progress: 1.0,
      );
      const pDifferentProgress = AppBarFocusRingPainter(
        isFocused: false,
        isHovered: false,
        isPressed: false,
        progress: 0.5,
      );

      expect(p1.shouldRepaint(p2), isFalse);
      expect(p1.shouldRepaint(pFocused), isTrue);
      expect(p1.shouldRepaint(pHovered), isTrue);
      expect(p1.shouldRepaint(pPressed), isTrue);
      expect(p1.shouldRepaint(pDifferentProgress), isTrue);
    });

    testWidgets('paints focused, hovered, pressed states without error', (tester) async {
      for (final state in [
        (focused: true, hovered: false, pressed: false),
        (focused: false, hovered: true, pressed: false),
        (focused: false, hovered: false, pressed: true),
        (focused: false, hovered: false, pressed: false),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: CustomPaint(
                  size: const Size(40, 32),
                  painter: AppBarFocusRingPainter(
                                isFocused: state.focused,
                    isHovered: state.hovered,
                    isPressed: state.pressed,
                    progress: 1.0,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });

    test('at rest it paints a 12% white glass circle with an 18% white hairline edge', () {
      const painter = AppBarFocusRingPainter(isFocused: false, isHovered: false, isPressed: false, progress: 0.0);
      expect(
        (Canvas canvas) => painter.paint(canvas, const Size(36, 36)),
        paints
          ..rrect(
            rrect: RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 36, 36), const Radius.circular(18)),
            color: Colors.white.withValues(alpha: 0.12),
            style: PaintingStyle.fill,
          )
          ..rrect(color: Colors.white.withValues(alpha: 0.18), style: PaintingStyle.stroke, strokeWidth: 1.0),
      );
    });

    test('focus brightens the circle to 30% white with a 70% white edge', () {
      const painter = AppBarFocusRingPainter(isFocused: true, isHovered: false, isPressed: false, progress: 1.0);
      expect(
        (Canvas canvas) => painter.paint(canvas, const Size(36, 36)),
        paints
          ..rrect(color: Colors.white.withValues(alpha: 0.30), style: PaintingStyle.fill)
          ..rrect(color: Colors.white.withValues(alpha: 0.70), style: PaintingStyle.stroke, strokeWidth: 1.5),
      );
    });

    testWidgets('handles empty or zero-progress gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CustomPaint(
                size: Size.zero,
                painter: AppBarFocusRingPainter(
                            isFocused: true,
                  isHovered: false,
                  isPressed: false,
                  progress: 0.0,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('AppBarFocusRing Widget', () {
    late MockSettingsService settingsService;
    late LauncherState launcherState;

    setUp(() {
      settingsService = MockSettingsService();
      launcherState = LauncherState();
    });

    Widget createTestWidget({required VoidCallback onPressed, FocusNode? focusNode}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settingsService),
          ChangeNotifierProvider<LauncherState>.value(value: launcherState),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppBarFocusRing(
                focusNode: focusNode,
                onPressed: onPressed,
                child: const Icon(Icons.settings),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('renders child icon and activates on tap', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(createTestWidget(onPressed: () => pressed = true));

      expect(find.byIcon(Icons.settings), findsOneWidget);

      await tester.tap(find.byType(AppBarFocusRing));
      await tester.pumpAndSettle();

      expect(pressed, isTrue);
    });

    testWidgets('activates on keyboard enter when focused', (tester) async {
      bool pressed = false;
      final focusNode = FocusNode();

      await tester.pumpWidget(createTestWidget(onPressed: () => pressed = true, focusNode: focusNode));

      focusNode.requestFocus();
      await tester.pumpAndSettle();

      expect(focusNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(pressed, isTrue);
      focusNode.dispose();
    });
  });
}

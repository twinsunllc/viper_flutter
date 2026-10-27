// The launcher's placement (D169, D295, D296, D335), screen names (D332) and the OS floor (D338).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viper_flutter/src/core/device.dart';
import 'package:viper_flutter/src/core/placement.dart';
import 'package:viper_flutter/src/core/screens.dart';
import 'package:viper_flutter/src/ui/sheet.dart';

const screen = Size(393, 852);
const safe = EdgeInsets.only(top: 59, bottom: 34);

void main() {
  group('placement', () {
    test('the project starts the round button bottom right, raised on a bottom spot', () {
      final layout = LauncherLayout.fromProject(
        ProjectPlacement.fromJson({'style': 'corner', 'spot': 'bottom-right', 'raise': 80}),
      );
      expect(layout.tucked, isFalse);
      expect(layout.buttonOffset(screen, safe), const Offset(393 - 16 - 52, 852 - 34 - 16 - 52 - 80));
    });

    test('a raise only applies to a bottom spot', () {
      final layout = LauncherLayout.fromProject(
        ProjectPlacement.fromJson({'style': 'corner', 'spot': 'top-left', 'raise': 80}),
      );
      expect(layout.raise, 0);
      expect(layout.buttonOffset(screen, safe), const Offset(16, 59 + 16));
    });

    test('an edge tab project starts tucked on its side at its height', () {
      final layout = LauncherLayout.fromProject(
        ProjectPlacement.fromJson({'style': 'edge_tab', 'edge_side': 'left', 'edge_position': 50}),
      );
      expect(layout.tucked, isTrue);
      final tab = layout.tabRect(screen, safe);
      expect(tab.left, -6);
      expect(tab.center.dy, 852 / 2);
    });

    test('bad values fall back to the protocol defaults', () {
      final project = ProjectPlacement.fromJson({
        'style': 'floating',
        'spot': 'middle',
        'raise': 9000,
        'edge_position': -5,
      });
      expect(
        (project.style, project.spot, project.raise, project.edgePosition),
        ('corner', 'bottom-right', 400.0, 0.0),
      );
      expect(ProjectPlacement.fromJson(null).spot, 'bottom-right');
    });

    test("what a person moved wins over the project's placement, and hidden is kept either way", () {
      final project = ProjectPlacement.fromJson({'style': 'corner', 'spot': 'bottom-right'});
      final moved = LauncherLayout.restore({
        'spot': 'top-left',
        'tucked': false,
        'moved': true,
        'hidden': true,
      }, project);
      expect((moved.spot, moved.hidden, moved.moved), ('top-left', true, true));
      final untouched = LauncherLayout.restore({'spot': 'top-left', 'moved': false, 'hidden': true}, project);
      expect((untouched.spot, untouched.hidden), ('bottom-right', true));
    });

    test('a drop snaps to the nearest of the eight spots', () {
      expect(nearestSpot(const Offset(20, 90), screen, safe), 'top-left');
      expect(nearestSpot(const Offset(170, 400), screen, safe), anyOf('left', 'right'));
      expect(nearestSpot(const Offset(320, 410), screen, safe), 'right');
      expect(nearestSpot(const Offset(170, 760), screen, safe), 'bottom');
    });

    test('kept and restored as JSON', () {
      const layout = LauncherLayout(spot: 'left', tucked: true, edgeSide: 'left', edgePosition: 30, moved: true);
      expect(LauncherLayout.restore(layout.toJson(), const ProjectPlacement()), layout);
    });
  });

  group('screen names (D332)', () {
    test('split a type on case and drop Screen', () {
      expect(displayName('CastHubScreen'), 'Cast hub');
      expect(displayName('JobDetailsPage'), 'Job details');
      expect(displayName('SettingsView'), 'Settings');
    });

    test('read a route name', () {
      expect(displayName('/'), 'Home');
      expect(displayName('/cast-hub'), 'Cast hub');
      expect(displayName('/jobs/:id/edit_details'), 'Edit details');
      expect(displayName('profile'), 'Profile');
    });

    test('keep an acronym', () {
      expect(displayName('FAQScreen'), 'FAQ');
      expect(displayName('ShowFAQPage'), 'Show FAQ');
    });
  });

  group('the OS floor (D338)', () {
    test('compares versions as numbers', () {
      expect(compareVersions('16.10', '16.4'), 1);
      expect(compareVersions('16.4', '16.4.0'), 0);
      expect(compareVersions('16.3.1', '16.4'), -1);
      expect(compareVersions('26.0', '16.4'), 1);
    });
  });

  group('the commit (D356)', () {
    test("reads VIPER_COMMIT trimmed, and nothing when CI didn't write one", () {
      expect(commitFrom(' 4f2a9c1e8b7d '), '4f2a9c1e8b7d');
      expect(commitFrom(''), isNull);
      expect(commitFrom('   '), isNull);
      // A test run is given no define.
      expect(viperCommitDefine, '');
    });
  });

  group('the sheet', () {
    test('is 82% of the screen, at most 720, and never above the safe area', () {
      expect(sheetHeight(height: 852, top: 59, keyboard: 0), closeTo(698.64, 0.01));
      expect(sheetHeight(height: 1366, top: 24, keyboard: 0), 720);
      expect(sheetHeight(height: 852, top: 59, keyboard: 336), 852 - 59 - 336 - 8);
    });
  });
}

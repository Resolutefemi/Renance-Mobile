// Founder pass IX screenshots: the REAL widgets rendered to PNG through
// the golden pipeline - the streak page (with the blue Streak-Freeze
// day), the feed-share achievement popup, and the achievement as it
// lands in the real FeedScreen. Run with:
//   flutter test --update-goldens test/goldens/pass_ix_screenshots_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renance/api_client.dart';
import 'package:renance/ui/achievement_share.dart';
import 'package:renance/ui/celebrations.dart';
import 'package:renance/ui/feed_screen.dart';
import 'package:renance/ui/theme.dart';

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildRenanceTheme(),
      home: child,
    ),
  );
}

void main() {
  testWidgets('streak page - flame, orange count-up, week row with the '
      'blue freeze day and the amber today ring', (WidgetTester tester) async {
    _phone(tester);
    await _pump(
      tester,
      // 13-day streak whose yesterday was saved by a Streak Freeze -
      // the founder's reference cut (blue day + perfect-week copy).
      const StreakScreen(streak: 13, forgiven: true),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('streak_page.png'),
    );
  });

  testWidgets('feed-share achievement popup - 14-day streak offer',
      (WidgetTester tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ApiClient api = ApiClient(
      baseUrl: 'https://goldens.renance.test',
      client: MockClient(
        (http.Request request) async => http.Response('{"ok":true}', 200),
      ),
    );
    late BuildContext captured;
    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[Provider<ApiClient>.value(value: api)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildRenanceTheme(),
          home: Builder(
            builder: (BuildContext ctx) {
              captured = ctx;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    );
    // ignore: discarded_futures
    maybeOfferStreakShare(captured, streak: 14);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('share_popup.png'),
    );
  });

  testWidgets('feed - the achievement post as the real FeedScreen renders '
      'it (milestone rail + a classmate post)', (WidgetTester tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final int now = DateTime.now().millisecondsSinceEpoch;
    final ApiClient api = ApiClient(
      baseUrl: 'https://goldens.renance.test',
      client: MockClient((http.Request request) async {
        final String url = request.url.toString();
        if (url.contains('/social/connections')) {
          return http.Response(
            '{"followers":[],"following":[]}',
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response(
          '{"posts":['
          '{"id":1042,"kind":"milestone","body":"Just hit a 14-day streak '
          'on Renance - consistency builds mastery. renance.app",'
          '"meta":{"streak":14},"likes":23,"comments":4,"likedByMe":false,'
          '"mine":false,"createdAtMs":${now - 2 * 3600 * 1000},'
          '"author":{"id":"u1","username":"resolute","name":"Resolute Femi",'
          '"premium":true}},'
          '{"id":1041,"kind":"user","body":"Finally topped my JAMB mock - '
          '311 over 400! The grind pays.","meta":null,"likes":47,'
          '"comments":8,"likedByMe":false,"mine":false,'
          '"createdAtMs":${now - 7 * 3600 * 1000},'
          '"author":{"id":"u2","username":"amaka_o","name":"Amaka O.",'
          '"premium":false}}'
          ']}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[Provider<ApiClient>.value(value: api)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildRenanceTheme(),
          home: const Scaffold(body: SafeArea(child: FeedScreen())),
        ),
      ),
    );
    // The load is a post-frame callback plus two awaited calls.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('feed_post.png'),
    );
    // Unmount so the poll Timer disposes clean.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

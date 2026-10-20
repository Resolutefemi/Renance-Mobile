/// University home, the Stitch university_home_dashboard_light screen,
/// 1:1, renamed the School Desk (founder rename). Rendered by the shell
/// instead of the JAMB launcher when the student's learning focus is a
/// tertiary institution: the school hero card (name, course count, the
/// Pick School button when nothing is picked yet), the Active Courses
/// chips row and the Practice / Grow grids. The school pick is stored
/// once (the founder rule): after that only the profile edit changes it.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers.dart';
import '../storage.dart';
import 'arena_lobby_screen.dart';
import 'downloads_screen.dart';
import 'gpa_screen.dart';
import 'home_screen.dart' show LauncherTile, showMoreSheet;
import 'leaderboard_screen.dart';
import 'lessons_screen.dart';
import 'msymbols.dart';
import 'review_screen.dart';
import 'study_plan_screen.dart';
import 'study_setup_screen.dart';
import 'tactile.dart';
import 'theme.dart';
import 'tutor_screen.dart';
import 'university_screens.dart';

class UniversityHomeTab extends StatelessWidget {
  /// "1668" -> "1,668" (the web's toLocaleString('en-US')).
  static String _formatThousands(int n) {
    final String raw = n.toString();
    final StringBuffer out = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (i > 0 && (raw.length - i) % 3 == 0) out.write(',');
      out.write(raw[i]);
    }
    return out.toString();
  }

  const UniversityHomeTab({
    super.key,
    required this.student,
    required this.sync,
    required this.onGoTab,
  });

  final StudentController student;
  final SyncController sync;
  final ValueChanged<int> onGoTab;

  /// The student's school: the stored pick first, then the profile
  /// institution match against the banked schools. Null = nothing picked
  /// yet, the desk shows its Pick School button.
  String? _schoolSlug(BuildContext context) {
    final Set<String> banked =
        universityCourses(sync.exams).keys.toSet();
    final String? stored = context
        .read<SessionStore>()
        .prefs
        .getString(kSchoolPickKey);
    if (stored != null && banked.contains(stored)) return stored;
    final String institution =
        student.me?.profile?.institution.trim().toLowerCase() ?? '';
    if (institution.isEmpty) return null;
    for (final MapEntry<String, (String, String)> e
        in kUniversitySchools.entries) {
      if (!banked.contains(e.key)) continue;
      final (String short, String full) = e.value;
      if (institution == e.key ||
          institution == short.toLowerCase() ||
          institution.contains(full.toLowerCase()) ||
          full.toLowerCase().contains(institution)) {
        return e.key;
      }
    }
    return null;
  }

  void _openDesk(BuildContext context) {
    // Founder directive (2026-10-16, the School Desk overhaul - web
    // parity): the tertiary student's primary CTA opens MY SEMESTER,
    // the gamified courses desk (courses tab), exactly like the web's
    // "Open your semester desk" -> /courses. The old school desk and
    // the picker stay reachable from the Active Courses strip.
    final String? slug = _schoolSlug(context);
    if (slug != null) {
      onGoTab(1); // the Courses tab - the My Semester dashboard
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UniversityPickerScreen(exams: sync.exams),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool syncing = sync.isSyncing;
    final Map<String, List<UniCourse>> schools = universityCourses(sync.exams);
    final String? slug = _schoolSlug(context);
    final List<UniCourse> schoolCourses =
        slug != null ? (schools[slug] ?? const <UniCourse>[]) : const <UniCourse>[];
    final (String short, String full) = slug != null
        ? (kUniversitySchools[slug]!.$1, kUniversitySchools[slug]!.$2)
        : ('School Desk', '${schools.length} banked schools');
    // The web's hero subtitle: "X courses · Y questions" - the LIVE
    // bank counts for the picked school.
    final int questionCount = schoolCourses.fold<int>(
        0, (int n, UniCourse c) => n + c.exam.questionCount);
    // Founder-only school switching (2026-10-04): the "All schools"
    // escape hatch is the founder's; students live on their own desk.
    final bool founder =
        (student.me?.email ?? '').trim().toLowerCase() ==
            'ariyooluwafemi487@gmail.com';

    return RefreshIndicator(
      onRefresh: student.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(context).top +74,
          16,
          // the web's pb-28: clear of the AI sparkle button
          112,
        ),
        children: <Widget>[
          // School hero card ----------------------------------------------
          _SchoolHeroCard(
            syncing: syncing,
            heroShort: short,
            heroName: slug != null ? full : 'Pick your school',
            subtitle: slug != null && schoolCourses.isNotEmpty
                ? '${schoolCourses.length} courses'
                  ' · ${_formatThousands(questionCount)} questions'
                : 'Course content lands as it is harvested',
            picked: slug != null,
            onOpen: () => _openDesk(context),
          ),
          // Course chips row ----------------------------------------------
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('Active Courses', style: RenanceText.sectionTitle.copyWith(fontSize: 16)),
              // Founder-only (2026-10-04): for students the desk shows
              // their own school's courses, never the all-schools gate.
              if (founder)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          UniversityPickerScreen(exams: sync.exams),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('All schools',
                      style: RenanceText.caption.copyWith(
                          fontSize: 13, color: context.textSecondary)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: schoolCourses.isEmpty
                ? ListView(
                    scrollDirection: Axis.horizontal,
                    children: <Widget>[
                      for (final String s in schools.keys.take(6))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _CourseChip(
                              (kUniversitySchools[s] ?? (s.toUpperCase(), s)).$1,
                              false),
                        ),
                    ],
                  )
                : ListView(
                    scrollDirection: Axis.horizontal,
                    children: <Widget>[
                      for (final UniCourse c in schoolCourses.take(6))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _CourseChip(c.label, false),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          // Study grid - the web's university desk icons
          Text(
            'Study',
            style: RenanceText.sectionTitle.copyWith(
              color: context.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: LauncherTile(
                  msIcon: 'assignment',
                  label: 'Courses',
                  // the web's Courses tile: the gamified My Semester
                  badge: student.dueTopics > 0 ? '${student.dueTopics}' : null,
                  badgeColor: RenanceColors.emerald,
                  onTap: () => onGoTab(1),
                ),
              ),
              Expanded(
                child: LauncherTile(
                  msIcon: 'fact_check',
                  label: 'Quizzes',
                  // the school's own course banks (web /university/<slug>)
                  onTap: () => _openSchoolBanks(context, slug, schoolCourses),
                ),
              ),
              Expanded(
                child: LauncherTile(
                  msIcon: 'local_library',
                  label: 'Study',
                  // founder directive (2026-10-04): the university desk's
                  // Study tile opens the SCHOOL past-questions setup,
                  // never the JAMB default.
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const StudySetupScreen()),
                  ),
                ),
              ),
              Expanded(
                child: LauncherTile(
                  msIcon: 'rate_review',
                  label: 'Review',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const ReviewScreen()),
                  ),
                ),
              ),
            ],
          ),
          // Grow grid - the web's exact four
          const SizedBox(height: 16),
          Text(
            'Grow',
            style: RenanceText.sectionTitle.copyWith(
              color: context.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: LauncherTile(
                  msIcon: 'calculate',
                  label: 'CGPA',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const GpaScreen()),
                  ),
                ),
              ),
              Expanded(
                child: LauncherTile(
                  msIcon: 'sports_esports',
                  label: 'Arena',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const ArenaLobbyScreen()),
                  ),
                ),
              ),
              Expanded(
                child: LauncherTile(
                  msIcon: 'leaderboard',
                  label: 'Leaderboard',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const LeaderboardScreen()),
                  ),
                ),
              ),
              Expanded(
                child: LauncherTile(
                  msIcon: 'event_note',
                  label: 'Study Plan',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const StudyPlanScreen()),
                  ),
                ),
              ),
            ],
          ),
          // Tools & Resources - shared with the other desks
          const SizedBox(height: 16),
          Text(
            'Tools & Resources',
            style: RenanceText.sectionTitle.copyWith(
              color: context.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: LauncherTile(
                  msIcon: 'import_contacts',
                  label: 'Notes',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const LessonsScreen()),
                  ),
                ),
              ),
              Expanded(
                child: LauncherTile(
                  msIcon: 'download',
                  label: 'Downloads',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const DownloadsScreen()),
                  ),
                ),
              ),
              Expanded(
                child: LauncherTile(
                  msIcon: 'smart_toy',
                  iconColor: context.onInverseChip,
                  highlight: true,
                  label: 'Tutor',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const TutorEntryScreen()),
                  ),
                ),
              ),
              Expanded(
                child: LauncherTile(
                  msIcon: 'more_horiz',
                  iconColor: context.textSecondary,
                  muted: true,
                  label: 'More',
                  onTap: () => showMoreSheet(context, onGoTab: onGoTab),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The web's Quizzes tile: the picked school's own course-bank desk
  /// (/university/SLUG). Nothing picked yet falls back to the picker.
  void _openSchoolBanks(
      BuildContext context, String? slug, List<UniCourse> courses) {
    if (slug == null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UniversityPickerScreen(exams: sync.exams),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            UniversityDeskScreen(schoolSlug: slug, courses: courses),
      ),
    );
  }
}

// ----------------------------------------------------------------- hero

/// The school hero card - the exact web twin of the dashboard's
/// UniversityHome hero (apps/web/app/dashboard/page.tsx): the
/// .hero-card 3D recipe, the "School Desk" mono eyebrow + school-short
/// badge, the institution title, the live "X courses · Y questions"
/// line and the 44px "Open your semester desk" CTA. The two corner
/// blobs (on-hero/12) stay from the founder's ornament directive.
class _SchoolHeroCard extends StatelessWidget {
  const _SchoolHeroCard({
    required this.syncing,
    required this.heroShort,
    required this.heroName,
    required this.subtitle,
    required this.picked,
    required this.onOpen,
  });

  final bool syncing;
  final String heroShort;
  final String heroName;
  final String subtitle;
  final bool picked;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final Color onHero = context.onHeroCard;
    return HeroCard(
      face: context.heroCard,
      onFace: onHero,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Stack(
        children: <Widget>[
          // corner blobs - the same clipped ornaments the web pins
          Positioned(
            top: -78,
            right: -50,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onHero.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            bottom: -62,
            left: -38,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onHero.withValues(alpha: 0.12),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  // the web's eyebrow: font-mono 10px w800 uppercase
                  // tracking-[0.2em] hero-muted
                  Text(
                    'SCHOOL DESK',
                    style: RenanceText.labelMono.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.0,
                      color: context.heroMuted,
                    ),
                  ),
                  // the web's school badge: rounded-full
                  // bg-dark-text-primary/15, school icon 13px + short
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: onHero.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        MsIcon('school',
                            size: 13, color: onHero, fill: true),
                        const SizedBox(width: 4),
                        Text(
                          syncing ? 'SYNCING' : heroShort,
                          style: RenanceText.labelMono.copyWith(
                            fontSize: 11,
                            color: onHero,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // title: text-xl font-bold tracking-tight
              Text(
                heroName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.15,
                  color: Color(0xFF3C3C46),
                ).copyWith(color: onHero),
              ),
              const SizedBox(height: 2),
              // subtitle: text-[13px] font-semibold hero-muted
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.heroMuted,
                ),
              ),
              const SizedBox(height: 12),
              // CTA: h-11 rounded-[10px] bg-hero-cta, school icon 18px
              TactileButton(
                height: 44,
                radius: BorderRadius.circular(10),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                face: context.heroCta,
                onFace: context.onHeroCta,
                edge: mixTowardBlack(context.heroCta, 0.68),
                onPressed: onOpen,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const MsIcon('school', size: 18, fill: true),
                    const SizedBox(width: 8),
                    Text(picked
                        ? 'Open your semester desk'
                        : 'Pick your school'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- chips

class _CourseChip extends StatelessWidget {
  const _CourseChip(this.label, this.selected);

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // The web's chip: rounded-full border-2 border-outline-variant/70
    // bg-surface-container-low px-3.5 text-[12px] font-semibold
    // on-surface-variant, 1px press sink.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: selected
            ? context.selectionBlue
            : context.cardLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: context.outlineVariant.withValues(alpha: 0.70),
          width: 2,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? context.ink : context.textSecondary,
        ),
      ),
    );
  }
}

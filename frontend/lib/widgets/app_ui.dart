import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/manila_time.dart';

/// One spacing scale for the whole app.
///
/// A screen whose gaps are 13, 17, 23 and 26 looks assembled rather than
/// designed, because nothing repeats. Everything comes from here instead.
class AppSpace {
  AppSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Three radii, one for each level of the layout: the card, a block inside a
/// card, and a pill. Using one radius everywhere flattens the hierarchy.
class AppRadius {
  AppRadius._();

  static const double card = 20;
  static const double block = 12;
  static const double pill = 999;
}

/// How serious a status is. The colour follows from this, never the reverse.
enum StatusLevel { good, caution, stop, neutral }

/// The colour a status is shown in.
///
/// One place decides, so the badge, the icon beside it and the sentence below
/// it can never disagree about whether the student is inside the campus. In
/// this app colour carries state and nothing else; it is never decoration.
class StatusTone {
  /// For text and icons.
  final Color content;

  /// The surface behind them.
  final Color container;

  final StatusLevel level;

  const StatusTone({
    required this.content,
    required this.container,
    required this.level,
  });

  static const _goodLight = StatusTone(
    content: Color(0xFF166F4A),
    container: Color(0xFFE3F3EB),
    level: StatusLevel.good,
  );
  static const _goodDark = StatusTone(
    content: Color(0xFF7FD3A8),
    container: Color(0xFF11372A),
    level: StatusLevel.good,
  );

  // Gold, from the school's shield, rather than a generic orange.
  static const _cautionLight = StatusTone(
    content: Color(0xFF8A6400),
    container: Color(0xFFFBF0D4),
    level: StatusLevel.caution,
  );
  static const _cautionDark = StatusTone(
    content: Color(0xFFE8C76A),
    container: Color(0xFF3A2E09),
    level: StatusLevel.caution,
  );

  static const _stopLight = StatusTone(
    content: Color(0xFFA4302A),
    container: Color(0xFFFBE6E4),
    level: StatusLevel.stop,
  );
  static const _stopDark = StatusTone(
    content: Color(0xFFF0A6A0),
    container: Color(0xFF40100D),
    level: StatusLevel.stop,
  );

  static StatusTone neutral(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StatusTone(
      content: scheme.onSurfaceVariant,
      container: scheme.surfaceContainerHighest,
      level: StatusLevel.neutral,
    );
  }

  /// The colour for a level chosen in code, for statuses whose wording does
  /// not say how serious they are ("Pending", "Timed out").
  static StatusTone forLevel(BuildContext context, StatusLevel level) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (level) {
      case StatusLevel.good:
        return dark ? _goodDark : _goodLight;
      case StatusLevel.caution:
        return dark ? _cautionDark : _cautionLight;
      case StatusLevel.stop:
        return dark ? _stopDark : _stopLight;
      case StatusLevel.neutral:
        return neutral(context);
    }
  }

  /// Reads a status written for a person — "Inside Campus", "On campus, late",
  /// "Outside Campus", "Present" — and answers with the colour it should wear.
  ///
  /// The order matters: "Not on campus" must be read as a refusal before
  /// "on campus" is read as a welcome, and "On campus, late" is a caution
  /// rather than a plain yes.
  static StatusTone of(BuildContext context, String label) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = label.toLowerCase();

    if (text.contains('not on campus') ||
        text.contains('outside') ||
        text.contains('absent') ||
        text.contains('permission') ||
        text.contains('denied')) {
      return dark ? _stopDark : _stopLight;
    }
    if (text.contains('late') ||
        text.contains('checking') ||
        text.contains('boundary') ||
        text.contains('near')) {
      return dark ? _cautionDark : _cautionLight;
    }
    if (text.contains('inside campus') ||
        text.contains('on campus') ||
        text.contains('present') ||
        text.contains('active')) {
      return dark ? _goodDark : _goodLight;
    }
    return neutral(context);
  }
}

/// One filter in a row of filters.
///
/// It always fills the width it is given and shortens a long name with "...",
/// so a course called "BS Information Technology" cannot push the filter
/// beside it off the edge of a phone.
class FilterDropdown extends StatelessWidget {
  final String value;

  /// Every choice, the "all" option first.
  final List<String> options;

  final IconData icon;
  final ValueChanged<String> onChanged;

  /// A filter with nothing to choose from is shown but cannot be opened, so
  /// the row does not change shape as the lists above it load.
  final bool enabled;

  const FilterDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.icon,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: options.contains(value) ? value : options.first,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: Icon(icon, size: 18),
        prefixIconConstraints: const BoxConstraints(minWidth: 34),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: 10,
        ),
      ),
      style: Theme.of(context).textTheme.bodyMedium,
      items: options
          .map(
            (option) => DropdownMenuItem(
              value: option,
              child: Text(option, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: !enabled || options.length < 2
          ? null
          : (chosen) {
              if (chosen == null || chosen == value) return;
              onChanged(chosen);
            },
    );
  }
}

/// Lays filters out so they fit the screen they are on.
///
/// On a laptop all in one row (two to a row on a small window). On a phone
/// only the first (usually the sort) stays out, beside a "Filters" button
/// that opens the rest: five filters stacked one under another took the
/// whole screen before the first name appeared. The button shows how many
/// filters are set, so a list that looks short is never a mystery.
///
/// [foldOnWide] keeps the phone layout on a laptop too: the first filter
/// and the "Filters" button, the rest side by side when opened. The class
/// schedule screen uses it, where the filters sit under a search box.
class FilterBar extends StatefulWidget {
  final List<Widget> children;
  final bool foldOnWide;

  const FilterBar({
    super.key,
    required this.children,
    this.foldOnWide = false,
  });

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  bool _open = false;

  /// Filters below the first that are set to something other than "all".
  int get _activeCount => widget.children
      .skip(1)
      .whereType<FilterDropdown>()
      .where((f) => f.options.isNotEmpty && f.value != f.options.first)
      .length;

  @override
  Widget build(BuildContext context) {
    final children = widget.children;
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpace.sm;
        final width = constraints.maxWidth;
        final wide = width >= 600;
        final fold = children.length > 2 && (!wide || widget.foldOnWide);

        if (!fold) {
          final columns = width >= 760
              ? children.length
              : width >= 340
              ? 2
              : 1;
          final itemWidth =
              ((width - gap * (columns - 1)) / columns).floorToDouble();
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final child in children)
                SizedBox(width: itemWidth, child: child),
            ],
          );
        }

        final theme = Theme.of(context);
        final active = _activeCount;
        final button = SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _open = !_open),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              backgroundColor: _open || active > 0
                  ? theme.colorScheme.primary.withValues(alpha: 0.08)
                  : null,
            ),
            icon: Icon(
              _open ? Icons.expand_less_rounded : Icons.tune_rounded,
              size: 18,
            ),
            label: Text(active > 0 ? 'Filters ($active)' : 'Filters'),
          ),
        );

        // Opened: side by side on a laptop, one per line on a phone.
        final rest = children.skip(1).toList();
        final restColumns = wide ? (width >= 1000 ? 4 : 3) : 1;
        final restWidth =
            ((width - gap * (restColumns - 1)) / restColumns).floorToDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (wide)
                  SizedBox(width: 260, child: children.first)
                else
                  Expanded(child: children.first),
                const SizedBox(width: gap),
                button,
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.only(top: gap),
                      child: Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final child in rest)
                            SizedBox(width: restWidth, child: child),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        );
      },
    );
  }
}

class SectionHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final subtitleText = subtitle;
    final trailingWidget = trailing;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              if (subtitleText case final subtitleText?) ...[
                const SizedBox(height: 4),
                Text(
                  subtitleText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailingWidget,
      ],
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color? color;

  /// Set when the wording alone does not say how serious the status is.
  final StatusTone? tone;

  const StatusBadge({super.key, required this.label, this.color, this.tone});

  @override
  Widget build(BuildContext context) {
    // The old version matched whole strings, so "Checking Location..." fell
    // through to the plain theme colour because of its three dots.
    final tone = this.tone ?? StatusTone.of(context, label);
    final content = color ?? tone.content;
    final container = color == null
        ? tone.container
        : color!.withValues(alpha: 0.12);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: content,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: scheme.primary, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            if (action case final action?) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  final String name;
  final double radius;

  /// Profile photo as a data URL ("data:image/jpeg;base64,..."). When it is
  /// null or cannot be read, the initials are shown instead.
  final String? photo;

  const ProfileAvatar({
    super.key,
    required this.name,
    this.radius = 25,
    this.photo,
  });

  // Decoding a photo on every rebuild would make it flicker, so keep the last one.
  static String? _cachedPhoto;
  static ImageProvider? _cachedImage;

  static ImageProvider? _imageFrom(String? photo) {
    if (photo == null || photo.isEmpty) return null;
    if (photo == _cachedPhoto) return _cachedImage;
    try {
      final comma = photo.indexOf(',');
      final bytes = base64Decode(
        comma >= 0 ? photo.substring(comma + 1) : photo,
      );
      _cachedPhoto = photo;
      _cachedImage = MemoryImage(bytes);
      return _cachedImage;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final image = _imageFrom(photo);
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: image,
      child: image != null
          ? null
          : Text(
              initials.isEmpty ? '?' : initials,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

// ── Motion and surfaces shared by every dashboard ─────────────────────────
//
// These began on the admin dashboard. They live here so the parent and
// teacher screens move and respond the same way instead of each inventing
// its own. Every one of them stands still for someone who has asked their
// phone for less motion.

/// A white surface with a hairline border instead of a shadow. When
/// [hovered], the border warms and the panel lifts a little.
class AppPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool hovered;

  /// A thin strip of colour down the left edge, for a panel whose whole
  /// meaning is a status (a child on campus, a request waiting).
  final Color? accent;

  const AppPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.hovered = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Padding(padding: padding, child: child);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(
          color: hovered
              ? theme.colorScheme.primary.withValues(alpha: 0.45)
              : theme.dividerColor,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: hovered
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      // The strip is laid over the left edge rather than set beside the
      // content in a measured row. Measuring first gave a ListTile with a
      // long subtitle too little height, which cut off its last line.
      child: accent == null
          ? body
          : Stack(
              children: [
                Padding(padding: const EdgeInsets.only(left: 4), child: body),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 4,
                  child: ColoredBox(color: accent!),
                ),
              ],
            ),
    );
  }
}

/// Anything that answers to the pointer: it tells [builder] when the mouse is
/// over it, shows a hand cursor, and handles the tap.
class Hoverable extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;

  const Hoverable({super.key, required this.builder, this.onTap});

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final content = widget.builder(context, _hovered);
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.onTap == null
          ? content
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: content,
            ),
    );
  }
}

/// Fades a block in and lifts it into place, [order] steps after the one
/// before it. Once, when the screen opens; never on scroll.
class Reveal extends StatelessWidget {
  final int order;
  final Widget child;

  const Reveal({super.key, required this.order, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    // Past the sixth block the wait would be felt, so they all arrive together.
    final step = order.clamp(0, 6);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + step * 70),
      curve: Curves.easeOutCubic,
      builder: (context, t, inner) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t)),
          child: inner,
        ),
      ),
      child: child,
    );
  }
}

/// Counts from zero up to [value] when a figure arrives.
class CountUp extends StatelessWidget {
  final int value;
  final TextStyle? style;

  const CountUp({super.key, required this.value, this.style});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text('$value', style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, shown, _) => Text('${shown.round()}', style: style),
    );
  }
}

/// A dot that breathes once a second: the page is live.
class LiveDot extends StatefulWidget {
  final Color color;

  const LiveDot({super.key, required this.color});

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (MediaQuery.disableAnimationsOf(context)) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: dot,
    );
  }
}

/// Today's date and the time in Manila, to the second, in a small pill.
///
/// It keeps its own one-second timer, so only the pill redraws each second
/// rather than the whole screen around it.
class LiveClock extends StatefulWidget {
  /// White on a translucent pill, for the green band.
  final bool onBrand;

  const LiveClock({super.key, this.onBrand = false});

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  DateTime _now = ManilaTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = ManilaTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onBrand = widget.onBrand;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: onBrand
            ? Colors.white.withValues(alpha: 0.14)
            : theme.cardColor,
        border: onBrand ? null : Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LiveDot(color: onBrand ? Colors.white : theme.colorScheme.primary),
          const SizedBox(width: AppSpace.sm),
          Text(
            MaterialLocalizations.of(context).formatMediumDate(_now),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              color: onBrand
                  ? Colors.white.withValues(alpha: 0.85)
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Text(
            ManilaTime.clockWithSeconds(_now),
            style: TextStyle(
              color: onBrand ? Colors.white : null,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// A row in a long list (users, attendance records, reports).
///
/// The same panel and hover as the dashboards, in place of a plain Card. The
/// first few rows arrive one after another when the list opens; rows further
/// down appear as they are, so scrolling never sets anything moving.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;

  /// The row's place in the list, for the entrance.
  final int index;

  /// A strip of colour down the left edge, such as an unread notification.
  final Color? accent;

  const AppCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.only(bottom: AppSpace.sm),
    this.index = 0,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final card = Padding(
      padding: margin,
      child: Hoverable(
        builder: (context, hovered) => AppPanel(
          hovered: hovered,
          accent: accent,
          padding: EdgeInsets.zero,
          // Lets a ListTile or InkWell inside draw its ripple on the panel
          // rather than underneath it.
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    );
    return index < 8 ? Reveal(order: index, child: card) : card;
  }
}

// ── The school's green header ─────────────────────────────────────────────
//
// The same top of the screen for every role: a green app bar with the
// shield, and a green band under it with the greeting and the time. It began
// on the admin dashboard; the student, teacher and parent homes use it too.

/// The shield and "BenildeSafe", set as a mark rather than as plain text.
class BrandMark extends StatelessWidget {
  final Color color;

  const BrandMark({super.key, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(2),
            child: Image.asset(
              'assets/benilde_shield.png',
              width: 26,
              height: 26,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Text(
          'BenildeSafe',
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}

/// A green app bar with the mark, and white icons for its [actions].
AppBar brandAppBar({List<Widget>? actions}) {
  return AppBar(
    backgroundColor: AppColors.forestGreen,
    foregroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    iconTheme: const IconThemeData(color: Colors.white),
    actionsIconTheme: const IconThemeData(color: Colors.white),
    titleSpacing: AppSpace.lg,
    title: const BrandMark(),
    actions: actions,
  );
}

/// The green band under [brandAppBar]: who is signed in, a line under it,
/// and the date and time in Manila.
///
/// It runs edge to edge, with its content kept to [maxWidth] so it lines up
/// with the page below. On a wide screen the clock sits at the right of the
/// greeting; on a phone it goes underneath.
class BrandBand extends StatelessWidget {
  final String greeting;
  final String? subtitle;

  /// For the initials in the avatar.
  final String name;
  final String? photo;
  final double maxWidth;

  const BrandBand({
    super.key,
    required this.greeting,
    required this.name,
    this.subtitle,
    this.photo,
    this.maxWidth = 960,
  });

  @override
  Widget build(BuildContext context) {
    final subtitleText = subtitle;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.forestGreen,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.card + 8),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 640;
              final who = Row(
                children: [
                  ProfileAvatar(name: name, radius: 24, photo: photo),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        if (subtitleText != null)
                          Text(
                            subtitleText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(width: AppSpace.lg),
                    const BrandClock(),
                  ],
                ],
              );
              if (wide) return who;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  who,
                  const SizedBox(height: AppSpace.lg),
                  const BrandClock(inRow: true),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The time in Manila, large, on the green band, with the date beside it.
///
/// The band has room to spare, and the time is what a student checks before
/// timing in, so it is set large rather than tucked into a small pill. It
/// keeps its own one-second timer, so only the clock redraws.
class BrandClock extends StatefulWidget {
  /// On a phone: the date on the left and the time on the right of one row
  /// across the band. Otherwise the date sits under the time, right-aligned.
  final bool inRow;

  const BrandClock({super.key, this.inRow = false});

  @override
  State<BrandClock> createState() => _BrandClockState();
}

class _BrandClockState extends State<BrandClock> {
  DateTime _now = ManilaTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = ManilaTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final minute = _now.minute.toString().padLeft(2, '0');
    final second = _now.second.toString().padLeft(2, '0');
    final period = _now.hour >= 12 ? 'PM' : 'AM';

    final time = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$hour:$minute',
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: ':$second',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          TextSpan(
            text: ' $period',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      style: const TextStyle(
        color: Colors.white,
        height: 1,
        letterSpacing: -0.5,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );

    final date = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LiveDot(color: Colors.white),
        const SizedBox(width: AppSpace.sm),
        Text(
          MaterialLocalizations.of(context).formatFullDate(_now),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    if (widget.inRow) {
      // The date on the left and the time on the right, both on one line
      // along the bottom of the band.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: FittedBox(fit: BoxFit.scaleDown, child: date),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          time,
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [time, const SizedBox(height: AppSpace.xs), date],
    );
  }
}

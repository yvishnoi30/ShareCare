import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'theme_controller.dart';

/// Returns [duration], or zero when the system asks for reduced motion.
Duration motionDuration(BuildContext context, Duration duration) {
  return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// "1 file" / "3 files".
String fileCountLabel(int count) => count == 1 ? '1 file' : '$count files';

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

/// The standard card: flat, with a hairline border instead of a shadow.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.radius = AppRadius.lg,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.cardSurface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: child,
    );
  }
}

/// A card heading with an optional action on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: context.text.titleLarge),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// A rounded tile holding a decorative icon.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.size = 44,
    this.background,
    this.foreground,
    this.circular = false,
  });

  final IconData icon;
  final double size;
  final Color? background;
  final Color? foreground;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.colors;

    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background ?? scheme.primaryContainer,
          shape: circular ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circular ? null : BorderRadius.circular(size * 0.3),
        ),
        child: Icon(
          icon,
          size: size * 0.5,
          color: foreground ?? scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

enum StatusTone { info, progress, success, warning, error }

/// Colors and default icon for a [StatusTone].
class ToneStyle {
  const ToneStyle({
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final Color background;
  final Color foreground;
  final IconData icon;

  factory ToneStyle.of(BuildContext context, StatusTone tone) {
    final ColorScheme scheme = context.colors;
    final StatusColors status = context.statusColors;

    if (tone == StatusTone.success) {
      return ToneStyle(
        background: status.successContainer,
        foreground: status.onSuccessContainer,
        icon: Icons.check_circle_rounded,
      );
    }

    if (tone == StatusTone.warning) {
      return ToneStyle(
        background: status.warningContainer,
        foreground: status.onWarningContainer,
        icon: Icons.warning_amber_rounded,
      );
    }

    if (tone == StatusTone.error) {
      return ToneStyle(
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        icon: Icons.error_outline_rounded,
      );
    }

    if (tone == StatusTone.progress) {
      return ToneStyle(
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
        icon: Icons.sync_rounded,
      );
    }

    return ToneStyle(
      background: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
      icon: Icons.info_outline_rounded,
    );
  }
}

/// A status message that always pairs color with an icon and text.
///
/// It is a live region, so screen readers announce changes.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.tone,
    required this.title,
    this.message,
    this.details,
    this.icon,
    this.progress,
    this.progressLabel,
  });

  final StatusTone tone;
  final String title;
  final String? message;
  final String? details;
  final IconData? icon;

  /// A real progress value between 0 and 1. Leave null when unknown.
  final double? progress;
  final String? progressLabel;

  @override
  Widget build(BuildContext context) {
    final ToneStyle style = ToneStyle.of(context, tone);
    final TextTheme text = context.text;
    final Duration duration =
        motionDuration(context, const Duration(milliseconds: 220));

    final String? messageText = message;
    final String? detailsText = details;
    final double? progressValue = progress;
    final String? progressText = progressLabel;

    final Widget leading = tone == StatusTone.progress
        ? ExcludeSemantics(
            child: SizedBox(
              width: 28,
              height: 28,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: style.foreground,
                ),
              ),
            ),
          )
        : ExcludeSemantics(
            child: Icon(icon ?? style.icon, size: 28, color: style.foreground),
          );

    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOut,
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: text.titleMedium?.copyWith(
                        color: style.foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (messageText != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        messageText,
                        style: text.bodyLarge?.copyWith(
                          color: style.foreground,
                        ),
                      ),
                    ],
                    if (detailsText != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      SelectableText(
                        detailsText,
                        style: text.bodyMedium?.copyWith(
                          color: style.foreground,
                        ),
                      ),
                    ],
                    if (progressValue != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      LinearProgressIndicator(
                        value: progressValue,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                        color: style.foreground,
                        backgroundColor: style.foreground.withAlpha(46),
                        semanticsLabel: 'Download progress',
                        semanticsValue:
                            '${(progressValue * 100).round()} percent',
                      ),
                      if (progressText != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          progressText,
                          style: text.bodyMedium?.copyWith(
                            color: style.foreground,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small pill with an icon and a short label.
class InfoChip extends StatelessWidget {
  const InfoChip({
    super.key,
    required this.icon,
    required this.label,
    this.tone,
  });

  final IconData icon;
  final String label;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.colors;
    final StatusTone? chipTone = tone;

    Color background = scheme.secondaryContainer;
    Color foreground = scheme.onSecondaryContainer;

    if (chipTone != null) {
      final ToneStyle style = ToneStyle.of(context, chipTone);
      background = style.background;
      foreground = style.foreground;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ExcludeSemantics(child: Icon(icon, size: 18, color: foreground)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: context.text.labelLarge?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lists and empty states
// ---------------------------------------------------------------------------

/// One file in a list: type icon, name, a subtitle and an optional action.
class FileTile extends StatelessWidget {
  const FileTile({
    super.key,
    required this.icon,
    required this.name,
    required this.subtitle,
    this.trailing,
    this.standalone = false,
  });

  final IconData icon;
  final String name;
  final Widget subtitle;
  final Widget? trailing;

  /// Use true when the tile sits directly on the page background instead of
  /// inside an [AppCard]. It then gets its own surface and border.
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    final Widget? action = trailing;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: standalone ? context.cardSurface : context.tileSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: standalone
            ? Border.all(color: context.colors.outlineVariant)
            : null,
      ),
      child: Row(
        children: <Widget>[
          IconBadge(icon: icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                subtitle,
              ],
            ),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            action,
          ],
        ],
      ),
    );
  }
}

/// Shown when a list has nothing in it yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxl,
        horizontal: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: context.tileSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: <Widget>[
          IconBadge(
            icon: icon,
            size: 56,
            circular: true,
            background: scheme.secondaryContainer,
            foreground: scheme.onSecondaryContainer,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.text.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One numbered step of a short sequence.
class StepRow extends StatelessWidget {
  const StepRow({
    super.key,
    required this.number,
    required this.title,
    required this.description,
  });

  final int number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.colors;

    return Semantics(
      container: true,
      label: 'Step $number: $title. $description',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$number',
                style: context.text.labelLarge?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: context.text.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: context.text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Actions and motion
// ---------------------------------------------------------------------------

/// Shrinks its child slightly while it is pressed.
///
/// It only listens to raw pointer events, so it never intercepts taps or
/// scrolling from the child.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.97,
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() {
      _pressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (widget.enabled) _setPressed(true);
      },
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed && widget.enabled ? widget.pressedScale : 1,
        duration: motionDuration(context, const Duration(milliseconds: 90)),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Fades and lifts its child into place once, when it first appears.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _started = false;

  @override
  void initState() {
    super.initState();

    final int totalMs =
        (widget.delay + widget.duration).inMilliseconds;

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );

    final double begin =
        totalMs == 0 ? 0 : widget.delay.inMilliseconds / totalMs;

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(begin, 1.0, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_started) return;
    _started = true;

    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: AnimatedBuilder(
        animation: _animation,
        child: widget.child,
        builder: (BuildContext context, Widget? child) {
          return Transform.translate(
            offset: Offset(0, (1 - _animation.value) * widget.offset),
            child: child,
          );
        },
      ),
    );
  }
}

/// A large, tappable card for a primary action on the home screen.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    required this.background,
    required this.foreground,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;

  /// Shows a spinner in place of the icon while an action is in progress.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final TextTheme text = context.text;

    final Widget leading = loading
        ? SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: foreground,
                ),
              ),
            ),
          )
        : IconBadge(
            icon: icon,
            size: 48,
            circular: true,
            background: foreground.withAlpha(30),
            foreground: foreground,
          );

    return PressableScale(
      enabled: enabled,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: '$title. $subtitle',
        onTap: onPressed,
        excludeSemantics: true,
        child: Opacity(
          opacity: enabled || loading ? 1 : 0.6,
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    leading,
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      title,
                      style: text.titleLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      style: text.bodyMedium?.copyWith(color: foreground),
                    ),
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

// ---------------------------------------------------------------------------
// Branding and theme switch
// ---------------------------------------------------------------------------

/// The ShareCare mark: two devices with a transfer badge.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.colors;
    final bool showBadge = size >= 48;
    final double badgeSize = size * 0.4;

    return Semantics(
      label: 'ShareCare logo',
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(size * 0.3),
                ),
                child: Center(
                  child: Icon(
                    Icons.devices_rounded,
                    size: size * 0.52,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            ),
            if (showBadge)
              Positioned(
                right: -size * 0.06,
                bottom: -size * 0.06,
                child: Container(
                  width: badgeSize,
                  height: badgeSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: size * 0.05,
                    ),
                  ),
                  child: Icon(
                    Icons.swap_horiz_rounded,
                    size: badgeSize * 0.62,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// App bar button that switches between light and dark mode.
///
/// It shows the icon of the mode you will switch to: a moon in light mode,
/// a sun in dark mode.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeController controller = ThemeScope.of(context);
    final bool isDark = context.isDarkTheme;

    return IconButton(
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      onPressed: () {
        controller.setMode(isDark ? ThemeMode.light : ThemeMode.dark);
      },
      icon: AnimatedSwitcher(
        duration: motionDuration(context, const Duration(milliseconds: 280)),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return RotationTransition(
            turns: Tween<double>(begin: 0.75, end: 1).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: Icon(
          isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          key: ValueKey<bool>(isDark),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:tracker/mockups/brand/brand_icons.dart';

/// An iPhone home screen (393 x 852 pt) with one brand's candidates in the top
/// row at the real 60 pt icon size, beside the current icon and neutral
/// placeholder apps.
class HomeScreenMock extends StatelessWidget {
  const HomeScreenMock({
    super.key,
    required this.brand,
    required this.currentIcon,
  });

  final Brand brand;
  final ImageProvider currentIcon;

  static const double iconSize = 60;

  static const List<(String, IconData, Color)> _placeholders = [
    ('Calendar', Icons.calendar_today, Color(0xFFE8E4DE)),
    ('Notes', Icons.sticky_note_2_outlined, Color(0xFFF2D46B)),
    ('Weather', Icons.wb_cloudy_outlined, Color(0xFF4F8BD6)),
    ('Clock', Icons.access_time, Color(0xFF2B2B2E)),
    ('Photos', Icons.filter_vintage_outlined, Color(0xFFEFEFEF)),
    ('Maps', Icons.map_outlined, Color(0xFF7CC38A)),
    ('Mail', Icons.mail_outline, Color(0xFF3D8EF0)),
    ('Music', Icons.music_note, Color(0xFFE5525F)),
    ('Books', Icons.menu_book_outlined, Color(0xFFF09A3E)),
    ('Podcasts', Icons.podcasts, Color(0xFF9B5DE5)),
    ('Files', Icons.folder_outlined, Color(0xFF5AA9F0)),
    ('Wallet', Icons.account_balance_wallet_outlined, Color(0xFF1F1F22)),
  ];

  static const List<(IconData, Color)> _dock = [
    (Icons.call, Color(0xFF4CD964)),
    (Icons.public, Color(0xFF3D8EF0)),
    (Icons.chat_bubble, Color(0xFF4CD964)),
    (Icons.photo_camera_outlined, Color(0xFF8E8E93)),
  ];

  Widget _placeholder(IconData glyph, Color colour) {
    final bool light = colour.computeLuminance() > 0.5;

    return MaskedIcon(
      size: iconSize,
      child: ColoredBox(
        color: colour,
        child: Icon(
          glyph,
          size: 32,
          color: light ? const Color(0xFF3A3A3C) : Colors.white,
        ),
      ),
    );
  }

  Widget _app(String label, Widget icon) {
    return SizedBox(
      width: 76,
      child: Column(
        children: [
          icon,
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              shadows: [Shadow(color: Color(0x66000000), blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> apps = [
      for (final IconCandidate candidate in brand.candidates)
        _app(
          '${brand.label} ${candidate.letter}',
          MaskedIcon.candidate(candidate, size: iconSize),
        ),
      _app(
        'Vice Tracker',
        MaskedIcon(
          size: iconSize,
          child: Image(image: currentIcon, fit: BoxFit.cover),
        ),
      ),
      for (final (String label, IconData glyph, Color colour) in _placeholders)
        _app(label, _placeholder(glyph, colour)),
    ];

    return SizedBox(
      width: 393,
      height: 852,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2F4A6E), Color(0xFF6E6A8F), Color(0xFFD49A85)],
          ),
        ),
        child: Column(
          children: [
            const _StatusBar(colour: Colors.white),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 22,
                children: apps,
              ),
            ),
            const Spacer(),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 22),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(34),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final (IconData glyph, Color colour) in _dock)
                    _placeholder(glyph, colour),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(44, 16, 30, 0),
        child: Row(
          children: [
            Text(
              '9:41',
              style: TextStyle(
                color: colour,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Icon(Icons.signal_cellular_alt, size: 18, color: colour),
            const SizedBox(width: 5),
            Icon(Icons.wifi, size: 18, color: colour),
            const SizedBox(width: 5),
            Icon(Icons.battery_full, size: 20, color: colour),
          ],
        ),
      ),
    );
  }
}

/// Every candidate side by side, at a large and a small (Settings, 29 pt)
/// size, with the current icon for comparison.
class IconOverview extends StatelessWidget {
  const IconOverview({super.key, required this.currentIcon});

  final ImageProvider currentIcon;

  Widget _tile(Widget large, Widget small, String title, String caption) {
    return SizedBox(
      width: 112,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [large, const SizedBox(width: 8), small],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            caption,
            maxLines: 2,
            style: const TextStyle(color: Color(0xFFB9B3C2), fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 393,
      height: 852,
      child: ColoredBox(
        color: const Color(0xFF0E0C11),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Icon candidates',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Each at 72 pt and at 29 pt (Settings, Spotlight).',
                style: TextStyle(color: Color(0xFFB9B3C2), fontSize: 13),
              ),
              const SizedBox(height: 16),
              _tile(
                MaskedIcon(
                  size: 72,
                  child: Image(image: currentIcon, fit: BoxFit.cover),
                ),
                MaskedIcon(
                  size: 29,
                  child: Image(image: currentIcon, fit: BoxFit.cover),
                ),
                'Current',
                'assets/icon.webp',
              ),
              for (final Brand brand in Brand.values) ...[
                const SizedBox(height: 14),
                Text(
                  '${brand.label}  ·  ${brand.meaning}',
                  style: const TextStyle(
                    color: IconPalette.coral,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final IconCandidate candidate in brand.candidates)
                      _tile(
                        MaskedIcon.candidate(candidate, size: 72),
                        MaskedIcon.candidate(candidate, size: 29),
                        '${candidate.letter}  ${candidate.title}',
                        candidate.description,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

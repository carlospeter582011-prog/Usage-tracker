import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'feature_language.dart';
import 'usage.dart';

extension NetworkDisplay on Network {
  IconData get icon => switch (this) {
    Network.wifi => Icons.wifi,
    Network.mobile => Icons.signal_cellular_alt,
    Network.both => Icons.layers_outlined,
  };

  String label(BuildContext context) => switch (this) {
    Network.wifi => 'Wi-Fi',
    Network.mobile => tr(context, 'Mobile data', 'داتا الموبايل'),
    Network.both => tr(context, 'Both', 'الاتنين'),
  };
}

class NetworkChoices extends StatelessWidget {
  const NetworkChoices({super.key, required this.selected, required this.onChanged});

  final Network selected;
  final ValueChanged<Network> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 6,
    children: [
      for (final network in [Network.wifi, Network.mobile, Network.both])
        ChoiceChip(
          avatar: Icon(network.icon, size: 16),
          label: Text(network.label(context)),
          selected: network == selected,
          onSelected: (selected) { if (selected) onChanged(network); },
        ),
    ],
  );
}

class TrackerLogo extends StatelessWidget {
  const TrackerLogo({super.key, this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF102F33),
        borderRadius: BorderRadius.circular(size * .24),
      ),
      child: CustomPaint(painter: _TrackerMark()),
    ),
  );
}

class _TrackerMark extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 108, size.height / 108);
    final paint = Paint()..color = const Color(0xFF69E0C3);
    final arc = Path()..moveTo(75, 29)
      ..arcToPoint(const Offset(31, 29), radius: const Radius.circular(33), largeArc: true);
    canvas.drawPath(arc, paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round);
    paint.style = PaintingStyle.fill;
    canvas.drawRect(const Rect.fromLTRB(36, 56, 45, 69), paint);
    canvas.drawRect(const Rect.fromLTRB(50, 47, 59, 69), paint);
    canvas.drawRect(const Rect.fromLTRB(64, 38, 73, 69), paint);
    canvas.drawCircle(const Offset(54, 22), 4, paint..color = const Color(0xFFFFC584));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrackerMark oldDelegate) => false;
}

class AppRow extends StatefulWidget {
  const AppRow({
    super.key, required this.app, required this.color,
    required this.total, required this.service,
  });

  final AppUsage app;
  final Color color;
  final int total;
  final UsageService service;

  @override
  State<AppRow> createState() => _AppRowState();
}

class _AppRowState extends State<AppRow> {
  late final Future<Uint8List?>? icon = switch (widget.app.package) {
    final String name when !name.contains(',') => widget.service.icon(name),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Icon(Icons.apps_rounded, color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: scheme.surface,
              child: SizedBox.square(
                dimension: 38,
                child: FutureBuilder<Uint8List?>(
                  future: icon,
                  builder: (_, snapshot) => snapshot.data == null
                      ? fallback
                      : Image.memory(snapshot.data!, errorBuilder: (_, _, _) => fallback),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(displayAppName(context, widget.app.name), style: const TextStyle(
                    fontWeight: FontWeight.w700))),
                  const SizedBox(width: 8),
                  Flexible(child: Text(formatBytes(widget.app.bytes),
                    textAlign: TextAlign.end, style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600))),
                ],
              ),
              if (widget.app.package case final String name)
                Text(name, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              Text('↓ ${formatBytes(widget.app.rx)}  ↑ ${formatBytes(widget.app.tx)}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: LinearProgressIndicator(
                  value: (widget.app.bytes / (widget.total > 0 ? widget.total : 1)).clamp(0.0, 1.0).toDouble(),
                  minHeight: 4, color: widget.color, backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],
          )),
        ],
      ),
    );
  }
}


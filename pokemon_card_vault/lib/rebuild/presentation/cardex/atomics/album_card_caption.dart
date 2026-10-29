import 'package:flutter/material.dart';

/// Thin metadata overlay: the name is already printed on the card itself.
class AlbumCardCaption extends StatelessWidget {
  const AlbumCardCaption(
      {super.key,
      required this.number,
      required this.expansion,
      this.overlay = false,
      this.status});
  final String number, expansion;
  final bool overlay;
  final String? status;

  /// Portfolio reserves two metadata lines, independent of loading/counts.
  static double footerHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(11) * 1.2 * 2 + 8;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(5, 3, 5, 5),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                [number, expansion]
                    .where((part) => part.isNotEmpty)
                    .join(' · '),
                maxLines:
                    overlay && MediaQuery.textScalerOf(context).scale(11) > 14
                        ? 1
                        : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    height: 1.2,
                    shadows: overlay
                        ? const [
                            Shadow(color: Colors.black, blurRadius: 3),
                            Shadow(
                                color: Colors.black,
                                blurRadius: 1,
                                offset: Offset(0, 1))
                          ]
                        : null)),
            if (status != null)
              Text(status!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      height: 1.2,
                      shadows: overlay
                          ? const [Shadow(color: Colors.black, blurRadius: 3)]
                          : null)),
          ]));
}

import 'package:flutter/material.dart';
import '../../../core/utils/hex_color.dart';
import '../competition_repository.dart';

class CompetitionCardStyle {
  final Color background, foreground, tint, border;
  CompetitionCardStyle(
    BuildContext context,
    CompetitionRow competition, {
    double strength = .14,
  }) : background = colorFromHex(
         (competition['fixture_type']
                 as Map?)?['colour_scheme']?['background_hex']
             ?.toString(),
         fallback: Theme.of(context).colorScheme.primary,
       ),
       foreground = colorFromHex(
         (competition['fixture_type']
                 as Map?)?['colour_scheme']?['foreground_hex']
             ?.toString(),
         fallback: Theme.of(context).colorScheme.onPrimary,
       ),
       tint = Color.alphaBlend(
         colorFromHex(
           (competition['fixture_type']
                   as Map?)?['colour_scheme']?['background_hex']
               ?.toString(),
           fallback: Theme.of(context).colorScheme.primary,
         ).withValues(alpha: strength),
         Theme.of(context).colorScheme.surface,
       ),
       border = colorFromHex(
         (competition['fixture_type']
                 as Map?)?['colour_scheme']?['background_hex']
             ?.toString(),
         fallback: Theme.of(context).colorScheme.primary,
       ).withValues(alpha: .5);
  ShapeBorder get shape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
    side: BorderSide(color: border),
  );
}

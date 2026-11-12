import 'package:flutter/widgets.dart';

String tr(BuildContext context, String en, String ar) =>
    Localizations.localeOf(context).languageCode == 'ar' ? ar : en;

String displayAppName(BuildContext context, String label) => switch (label) {
  'Shared Android UID' => tr(context, label, 'مجموعة تطبيقات أندرويد'),
  'Removed apps' => tr(context, label, 'تطبيقات محذوفة'),
  'Tethering' => tr(context, label, 'مشاركة الإنترنت'),
  'Android system' => tr(context, label, 'نظام أندرويد'),
  _ => label,
};

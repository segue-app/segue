import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/theme.dart';
import 'motion.dart';

import 'package:segue/core/l10n/l10n.dart';

/// "Support the author": the bank QR codes (Kyrgyzstan), Boosty from
/// anywhere, and a star on GitHub. The codes are bundled, so the sheet
/// works offline.
Future<void> showSupportSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: SegueColors.surface,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 520),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => const _SupportSheet(),
);

const boostyUrl = 'https://boosty.to/akjol_kan/donate';
const githubUrl = 'https://github.com/segue-app/segue';

class _SupportSheet extends StatelessWidget {
  const _SupportSheet();

  @override
  Widget build(BuildContext context) {
    // A phone can't scan its own screen: the bank app reads the code from
    // a screenshot instead.
    final phone = Platform.isAndroid || Platform.isIOS;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.favorite_rounded,
              color: Color(0xFFFF5E8A),
              size: 34,
            ),
            const SizedBox(height: 8),
            Text(
              'Поддержать Segue'.tr,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Segue бесплатный, без рекламы и подписок. Если он тебе нравится, можно поддержать автора — это помогает делать его дальше.'
                  .tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: SegueColors.textDim, height: 1.4),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Qr(asset: 'assets/support/mbank.png', name: 'Mbank'),
                const SizedBox(width: 12),
                _Qr(asset: 'assets/support/optima.png', name: 'Optima'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              phone
                  ? 'Кыргызстан: сделай снимок экрана и открой его в приложении банка (QR из галереи)'
                        .tr
                  : 'Кыргызстан: отсканируй телефоном в приложении банка (ELQR)'
                        .tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: SegueColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('support-boosty'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: SegueColors.accent,
                  foregroundColor: SegueColors.ink,
                ),
                onPressed: () => launchUrl(
                  Uri.parse(boostyUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.volunteer_activism_rounded),
                label: Text(
                  'Поддержать на Boosty (из любой страны)'.tr,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  foregroundColor: SegueColors.text,
                ),
                onPressed: () => launchUrl(
                  Uri.parse(githubUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.star_rounded),
                label: Text('Поставить звезду на GitHub'.tr),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Спасибо! Даже звезда на GitHub помогает другим найти Segue.'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: SegueColors.textDim, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _Qr extends StatelessWidget {
  const _Qr({required this.asset, required this.name});

  final String asset;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: PressScale(
          scale: 0.98,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  // Smooth downscaling keeps every module of the code.
                  child: Image.asset(
                    asset,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: const TextStyle(
                    color: SegueColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

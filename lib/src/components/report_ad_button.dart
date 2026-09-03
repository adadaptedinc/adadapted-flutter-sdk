/// The optional "report this ad" affordance shown over a filled zone.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The feedback page an ad is reported through.
const String _reportAdUrlBase = 'https://feedback.add-it.io/';

/// A small button that opens the ad feedback page for the ad on screen.
class ReportAdButton extends StatelessWidget {
  /// The ad ID of the current ad.
  final String adId;

  /// The current user's udid.
  final String udid;

  /// Creates a report ad button.
  /// @param adId - The ad ID of the current ad.
  /// @param udid - The current user's udid.
  const ReportAdButton({required this.adId, required this.udid, super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final url = Uri.parse(
          _reportAdUrlBase,
        ).replace(queryParameters: <String, String>{'aid': adId, 'uid': udid});

        // Errors are swallowed rather than thrown at the host: this is an
        // optional affordance over someone else's ad, and a device with no
        // browser to hand the URL to is not a reason to break the app it is
        // drawn in.
        unawaited(
          launchUrl(
            url,
            mode: LaunchMode.externalApplication,
          ).catchError((Object _) => false),
        );
      },
      child: Image.asset(
        'assets/report_icon.png',
        package: 'adadapted_flutter_sdk',
        width: 14,
        height: 14,
        // A missing or undecodable icon must not take the ad down with it. The
        // zone around this is a paying impression; the affordance over it is
        // not worth an exception in the host's render tree.
        errorBuilder: (_, _, _) => const SizedBox(width: 14, height: 14),
      ),
    );
  }
}

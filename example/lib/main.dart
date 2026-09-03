/// A test app for the AdAdapted Flutter SDK.
///
/// Two pages, because the interesting behaviour is what a zone does when it is
/// not being looked at: the second page keeps a zone mounted below the fold, so
/// its countdown and its impressions can be watched pausing and resuming.
library;

import 'package:adadapted_flutter_sdk/adadapted_flutter_sdk.dart';
import 'package:flutter/material.dart';

/// The app ID this demo serves ads for.
const String demoAppId = '7D58810X6333241C';

/// The zone the demo places on its home page.
///
/// A real dev-environment zone for [demoAppId], the same one the React Native
/// demo uses. Do not substitute a zone ID taken from the SDK's mock fixtures:
/// those are invented, and the API answers `success: false` for them, which the
/// SDK correctly reports as an unfilled zone and collapses.
const String demoZoneId = '102110';

/// The zone the off-screen page places.
///
/// Deliberately a different zone from [demoZoneId], so the two are served and
/// reported independently and it is obvious which one is which.
const String demoOffScreenZoneId = '110003';

void main() {
  runApp(const DemoApp());
}

/// The demo app.
class DemoApp extends StatefulWidget {
  /// Creates the demo app.
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  /// The SDK instance the whole app shares.
  final AdadaptedFlutterSdk _sdk = AdadaptedFlutterSdk();

  /// The items the user has "added to their list".
  final List<String> _list = <String>[];

  /// The session ID, once initialize() has resolved.
  String? _sessionId;

  /// Anything that went wrong during initialize().
  String? _error;

  @override
  void initState() {
    super.initState();

    _initializeSdk();
  }

  @override
  void dispose() {
    // Unmount the SDK, otherwise you can experience memory leaks.
    _sdk.unmount();

    super.dispose();
  }

  /// Starts the SDK and records the session it minted.
  Future<void> _initializeSdk() async {
    try {
      await _sdk.initialize(
        appId: demoAppId,
        apiEnv: ApiEnv.dev,
        // Optional custom advertiser ID — remove to use the IDFA instead.
        advertiserId: 'FLUTTER-TEST-ADVERTISER-ID',
        xyDragDistanceAllowed: 30,
        onAddToListTriggered: (items) {
          for (final item in items) {
            _selectItem(item.productTitle);
          }
        },
        onOutOfAppPayloadAvailable: (payloads) {
          for (final payload in payloads) {
            for (final item in payload.detailedListItems) {
              _selectItem(item.productTitle);
            }

            // Mark this payload as acknowledged.
            _sdk.markPayloadContentAcknowledged(payload.payloadId);
          }
        },
      );

      if (!mounted) {
        return;
      }

      // The session is generated locally, so it is available as soon as
      // initialize() resolves.
      setState(() {
        _sessionId = _sdk.sessionId;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    }
  }

  /// Adds an item to the demo's list and reports it.
  /// @param itemName - The item the user added.
  void _selectItem(String itemName) {
    // Acknowledge the item added to the user's list, which is what earns an
    // add-to-list ad its interaction.
    _sdk.acknowledge(itemName);

    // Report the item as added, ad-sourced or not.
    _sdk.reportItemsAddedToList(<String>[itemName], 'My grocery list');

    if (!mounted) {
      return;
    }

    setState(() {
      _list.add(itemName);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AdAdapted Flutter SDK',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: DemoHome(
        sdk: _sdk,
        sessionId: _sessionId,
        error: _error,
        list: _list,
        onSelectItem: _selectItem,
      ),
    );
  }
}

/// The demo's home page.
class DemoHome extends StatefulWidget {
  /// The SDK instance.
  final AdadaptedFlutterSdk sdk;

  /// The current session ID, once there is one.
  final String? sessionId;

  /// Anything that went wrong during initialize().
  final String? error;

  /// The items the user has added.
  final List<String> list;

  /// Adds an item to the list.
  final void Function(String itemName) onSelectItem;

  /// Creates the home page.
  const DemoHome({
    required this.sdk,
    required this.sessionId,
    required this.error,
    required this.list,
    required this.onSelectItem,
    super.key,
  });

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  /// The current search box contents.
  final TextEditingController _searchController = TextEditingController();

  /// The keyword intercept terms matching the current search.
  List<KeywordSearchResult> _results = <KeywordSearchResult>[];

  /// Whether the zone currently has an ad, as the SDK reported it.
  bool _zoneHasAds = false;

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  /// Runs a keyword search and reports which terms were shown.
  /// @param term - What the user typed.
  void _search(String term) {
    final results = widget.sdk.performKeywordSearch(term);

    if (results.isNotEmpty) {
      // Only the terms actually presented to the user are reported.
      widget.sdk.reportKeywordInterceptTermsPresented(
        results.map((result) => result.termId).toList(),
      );
    }

    setState(() {
      _results = results;
    });
  }

  /// Records that the user picked a suggested term.
  /// @param result - The term the user picked.
  void _selectTerm(KeywordSearchResult result) {
    widget.sdk.reportKeywordInterceptTermSelected(result.termId);
    widget.onSelectItem(result.replacement);

    _searchController.clear();

    setState(() {
      _results = <KeywordSearchResult>[];
    });
  }

  /// Describes the advertising identifier the SDK gathered, or why there is
  /// none to show.
  String _describeUdid() {
    final deviceInfo = widget.sdk.deviceInfo;

    if (deviceInfo == null) {
      return 'starting…';
    }

    if (deviceInfo.udid.isEmpty) {
      return '(none — ad tracking not permitted or unavailable)';
    }

    return deviceInfo.udid;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AdAdapted Flutter SDK')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Session: ${widget.sessionId ?? 'starting…'}'),
          // Shown because this is the field an emulator handles differently: a
          // simulator has no real advertising identifier, and an Android image
          // without Play Services has none either, so an empty value here is
          // the environment rather than a fault in the SDK.
          Text('Device ID: ${_describeUdid()}'),
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                widget.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),

          // The zone collapses to nothing when it has no ad, so the space
          // around it is the host's to manage — which is what onZoneHasAds is
          // for.
          if (_zoneHasAds) const SizedBox(height: 8),
          SizedBox(
            height: _zoneHasAds ? 250 : 0,
            child: AdZone(
              zoneId: demoZoneId,
              onZoneHasAds: (hasAds) {
                setState(() {
                  _zoneHasAds = hasAds;
                });
              },
            ),
          ),

          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: _search,
            decoration: const InputDecoration(
              labelText: 'Search your list',
              helperText: 'Try "milk" — matches need at least 3 characters.',
              border: OutlineInputBorder(),
            ),
          ),
          for (final result in _results)
            ListTile(
              title: Text(result.replacement),
              subtitle: Text('matched "${result.term}"'),
              onTap: () => _selectTerm(result),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              final term = _searchController.text.trim();

              if (term.isEmpty) {
                return;
              }

              widget.onSelectItem(term);

              _searchController.clear();

              setState(() {
                _results = <KeywordSearchResult>[];
              });
            },
            child: const Text('Add typed item to list'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const OffScreenZonePage(),
                ),
              );
            },
            child: const Text('Off-screen zone page'),
          ),
          const SizedBox(height: 16),
          const Text('My grocery list', style: TextStyle(fontSize: 18)),
          for (final item in widget.list)
            ListTile(dense: true, title: Text(item)),
        ],
      ),
    );
  }
}

/// A page whose zone starts well below the fold.
///
/// Scroll it into view and the zone starts its countdown and reports its
/// impression; scroll it away and both stop. Nothing here reports visibility to
/// the SDK — the zone measures its own.
class OffScreenZonePage extends StatelessWidget {
  /// Creates the off-screen zone page.
  const OffScreenZonePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Off-screen zone')),
      body: ListView(
        children: <Widget>[
          const SizedBox(
            height: 900,
            child: Center(child: Text('Scroll down to reach the zone.')),
          ),
          const SizedBox(
            height: 250,
            child: AdZone(zoneId: demoOffScreenZoneId),
          ),
          const SizedBox(
            height: 900,
            child: Center(child: Text('Scroll back up.')),
          ),
        ],
      ),
    );
  }
}

/// A [WebViewPlatform] that renders nothing and lets a test drive the load and
/// error callbacks by hand.
///
/// `WebViewController` refuses to be built without a registered platform, so an
/// [AdZone] cannot be pumped at all in a unit test without this. It also gives
/// the tests the only lever that matters for impression accounting: a creative
/// "finishing" or "failing" on demand.
library;

import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// The controllers built during the current test, newest last.
final List<FakeWebViewController> fakeWebViewControllers =
    <FakeWebViewController>[];

/// Installs the fake platform and clears anything a previous test left behind.
void installFakeWebViewPlatform() {
  fakeWebViewControllers.clear();

  WebViewPlatform.instance = FakeWebViewPlatform();
}

/// A [WebViewPlatform] whose every product is inert and inspectable.
class FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakeWebViewController(params);

    fakeWebViewControllers.add(controller);

    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return FakeNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return FakeWebViewWidget(params);
  }
}

/// Records what the SDK asked the web view to do.
class FakeWebViewController extends PlatformWebViewController {
  /// Creates a fake controller.
  FakeWebViewController(super.params) : super.implementation();

  /// Every URL that has been loaded, in order.
  final List<String> loadedUrls = <String>[];

  /// Every script that has been run, in order.
  final List<String> runJavaScripts = <String>[];

  /// The delegate the SDK attached, once it has.
  FakeNavigationDelegate? delegate;

  /// When set, the next [loadRequest] fails with this error.
  Object? loadRequestError;

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    if (loadRequestError != null) {
      final error = loadRequestError!;

      loadRequestError = null;

      throw error;
    }

    loadedUrls.add(params.uri.toString());
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate newDelegate,
  ) async {
    delegate = newDelegate as FakeNavigationDelegate;
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    runJavaScripts.add(javaScript);
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  /// Tells the SDK the creative finished rendering.
  void finishLoad() {
    delegate?.onPageFinished?.call(loadedUrls.isEmpty ? '' : loadedUrls.last);
  }

  /// Tells the SDK the creative failed to render.
  /// @param isForMainFrame - Whether the failure was the main frame. A
  ///      sub-resource failure must not discard a real fill.
  /// @param errorCode - The platform error code. -999 is WebKit's
  ///      NSURLErrorCancelled, raised when a load is superseded.
  /// @param url - The URL the failure belongs to, when the platform reports one.
  void failLoad({bool isForMainFrame = true, int errorCode = -1, String? url}) {
    delegate?.onWebResourceError?.call(
      FakeWebResourceError(
        isForMainFrame: isForMainFrame,
        errorCode: errorCode,
        url: url,
      ),
    );
  }
}

/// Captures the navigation callbacks so a test can fire them.
class FakeNavigationDelegate extends PlatformNavigationDelegate {
  /// Creates a fake navigation delegate.
  FakeNavigationDelegate(super.params) : super.implementation();

  /// The page finished callback the SDK registered.
  PageEventCallback? onPageFinished;

  /// The resource error callback the SDK registered.
  WebResourceErrorCallback? onWebResourceError;

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    onPageFinished = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    onWebResourceError = callback;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {}

  @override
  Future<void> setOnProgress(ProgressCallback callback) async {}

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}

  @override
  Future<void> setOnUrlChange(UrlChangeCallback callback) async {}

  @override
  Future<void> setOnHttpAuthRequest(HttpAuthRequestCallback callback) async {}

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async {}
}

/// A web resource error a test can raise.
class FakeWebResourceError extends WebResourceError {
  /// Creates a fake web resource error.
  /// @param isForMainFrame - Whether the failure was the main frame.
  /// @param errorCode - The platform error code.
  /// @param url - The URL the failure belongs to, if any.
  // ignore: prefer_const_constructors_in_immutables
  FakeWebResourceError({
    required bool isForMainFrame,
    super.errorCode = -1,
    super.url,
  }) : super(description: 'fake failure', isForMainFrame: isForMainFrame);
}

/// Renders nothing, because there is no platform view to embed in a unit test.
class FakeWebViewWidget extends PlatformWebViewWidget {
  /// Creates a fake web view widget.
  FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}

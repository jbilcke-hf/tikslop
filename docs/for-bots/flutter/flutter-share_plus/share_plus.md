[![](/static/hash-9gbn097u/img/ff-banner-desktop-2x.png)![](/static/hash-9gbn097u/img/ff-banner-desktop-dark-2x.png)![](/static/hash-9gbn097u/img/ff-banner-mobile-2x.png)![](/static/hash-9gbn097u/img/ff-banner-mobile-dark-2x.png)](https://flutter.dev/docs/development/packages-and-plugins/favorites "Package is a Flutter Favorite")

share\_plus 11.0.0 ![copy "share_plus: ^11.0.0" to clipboard](/static/hash-9gbn097u/img/content-copy-icon.svg "Copy "share_plus: ^11.0.0" to clipboard")

share\_plus: ^11.0.0 copied to clipboard


====================================================================================================================================================================================================

Published 15 days ago • [![verified publisher](/static/hash-9gbn097u/img/material-icon-verified.svg "Published by a pub.dev verified publisher")fluttercommunity.dev](/publishers/fluttercommunity.dev)Dart 3 compatible

SDK[Flutter](/packages?q=sdk%3Aflutter "Packages compatible with Flutter SDK")

Platform[Android](/packages?q=platform%3Aandroid "Packages compatible with Android platform")[iOS](/packages?q=platform%3Aios "Packages compatible with iOS platform")[Linux](/packages?q=platform%3Alinux "Packages compatible with Linux platform")[macOS](/packages?q=platform%3Amacos "Packages compatible with macOS platform")[web](/packages?q=platform%3Aweb "Packages compatible with Web platform")[Windows](/packages?q=platform%3Awindows "Packages compatible with Windows platform")

![liked status: inactive](/static/hash-9gbn097u/img/like-inactive.svg)![liked status: active](/static/hash-9gbn097u/img/like-active.svg)3.6k

→

### Metadata

Flutter plugin for sharing content via the platform share UI, using the ACTION\_SEND intent on Android and UIActivityViewController on iOS.

More...

*   Readme
*   [Changelog](/packages/share_plus/changelog)
*   [Example](/packages/share_plus/example)
*   [Installing](/packages/share_plus/install)
*   [Versions](/packages/share_plus/versions)
*   [Scores](/packages/share_plus/score)

share\_plus [#](#share_plus)
============================

[![share_plus](https://github.com/fluttercommunity/plus_plugins/actions/workflows/share_plus.yaml/badge.svg)](https://github.com/fluttercommunity/plus_plugins/actions/workflows/share_plus.yaml) [![pub points](https://img.shields.io/pub/points/share_plus?color=2E8B57&label=pub%20points)](https://pub.dev/packages/share_plus/score) [![pub package](https://img.shields.io/pub/v/share_plus.svg)](https://pub.dev/packages/share_plus)

[![](https://github.com/fluttercommunity/plus_plugins/raw/main/assets/flutter-favorite-badge.png)](https://flutter.dev/docs/development/packages-and-plugins/favorites)

A Flutter plugin to share content from your Flutter app via the platform's share dialog.

Wraps the `ACTION_SEND` Intent on Android, `UIActivityViewController` on iOS, or equivalent platform content sharing methods.

Platform Support [#](#platform-support)
---------------------------------------

Shared content

Android

iOS

MacOS

Web

Linux

Windows

Text

✅

✅

✅

✅

✅

✅

URI

✅

✅

✅

As text

As text

As text

Files

✅

✅

✅

✅

❌

✅

Also compatible with Windows and Linux by using "mailto" to share text via Email.

Sharing files is not supported on Linux.

Requirements [#](#requirements)
-------------------------------

*   Flutter >=3.22.0
*   Dart >=3.4.0 <4.0.0
*   iOS >=12.0
*   MacOS >=10.14
*   Android `compileSDK` 34
*   Java 17
*   Android Gradle Plugin >=8.3.0
*   Gradle wrapper >=8.4

Usage [#](#usage)
-----------------

To use this plugin, add `share_plus` as a [dependency in your pubspec.yaml file](https://plus.fluttercommunity.dev/docs/overview).

Import the library.

    import 'package:share_plus/share_plus.dart';
    

copied to clipboard

### Share Text [#](#share-text)

Access the `SharePlus` instance via `SharePlus.instance`. Then, invoke the `share()` method anywhere in your Dart code.

    SharePlus.instance.share(
      ShareParams(text: 'check out my website https://example.com')
    );
    

copied to clipboard

The `share()` method requires the `ShareParams` object, which contains the content to share.

These are some of the accepted parameters of the `ShareParams` class:

*   `text`: text to share.
*   `title`: content or share-sheet title (if supported).
*   `subject`: email subject (if supported).

Check the class documentation for more details.

`share()` returns `status` object that allows to check the result of user action in the share sheet.

    final result = await SharePlus.instance.share(params);
    
    if (result.status == ShareResultStatus.success) {
        print('Thank you for sharing my website!');
    }
    

copied to clipboard

### Share Files [#](#share-files)

To share one or multiple files, provide the `files` list in `ShareParams`. Optionally, you can pass `title`, `text` and `sharePositionOrigin`.

    final params = ShareParams(
      text: 'Great picture',
      files: [XFile('${directory.path}/image.jpg')], 
    );
    
    final result = await SharePlus.instance.share(params);
    
    if (result.status == ShareResultStatus.success) {
        print('Thank you for sharing the picture!');
    }
    

copied to clipboard

    final params = ShareParams(
      files: [
        XFile('${directory.path}/image1.jpg'), 
        XFile('${directory.path}/image2.jpg'),
      ],
    );
    
    final result = await SharePlus.instance.share(params);
    
    if (result.status == ShareResultStatus.dismissed) {
        print('Did you not like the pictures?');
    }
    

copied to clipboard

On web, this uses the [Web Share API](https://web.dev/web-share/) if it's available. Otherwise it falls back to downloading the shared files. See [Can I Use - Web Share API](https://caniuse.com/web-share) to understand which browsers are supported. This builds on the [`cross_file`](https://pub.dev/packages/cross_file) package.

File downloading fallback mechanism for web can be disabled by setting:

    ShareParams(
      // rest of params
      downloadFallbackEnabled: false,
    )
    

copied to clipboard

#### Share Data

You can also share files that you dynamically generate from its data using [`XFile.fromData`](https://pub.dev/documentation/share_plus/latest/share_plus/XFile/XFile.fromData.html).

To set the name of such files, use the `fileNameOverrides` parameter, otherwise the file name will be a random UUID string.

    final params = ShareParams(
      files: [XFile.fromData(utf8.encode(text), mimeType: 'text/plain')], 
      fileNameOverrides: ['myfile.txt']
    );
    
    SharePlus.instance.share(params);
    

copied to clipboard

Caution

The `name` parameter in the `XFile.fromData` method is ignored in most platforms. Use `fileNameOverrides` instead.

### Share URI [#](#share-uri)

iOS supports fetching metadata from a URI when shared using `UIActivityViewController`. This special functionality is only properly supported on iOS. On other platforms, the URI will be shared as plain text.

    final params = ShareParams(uri: uri);
    
    SharePlus.instance.share(params);
    

copied to clipboard

### Share Results [#](#share-results)

All three methods return a `ShareResult` object which contains the following information:

*   `status`: a `ShareResultStatus`
*   `raw`: a `String` describing the share result, e.g. the opening app ID.

Note: `status` will be `ShareResultStatus.unavailable` if the platform does not support identifying the user action.

Known Issues [#](#known-issues)
-------------------------------

### Sharing data created with XFile.fromData [#](#sharing-data-created-with-xfilefromdata)

When sharing data created with `XFile.fromData`, the plugin will write a temporal file inside the cache directory of the app, so it can be shared.

Although the OS should take care of deleting those files, it is advised, that you clean up this data once in a while (e.g. on app start).

You can access this directory using [path\_provider](https://pub.dev/packages/path_provider) [getTemporaryDirectory](https://pub.dev/documentation/path_provider/latest/path_provider/getTemporaryDirectory.html).

Alternatively, don't use `XFile.fromData` and instead write the data down to a `File` with a path before sharing it, so you control when to delete it.

### Mobile platforms (Android and iOS) [#](#mobile-platforms-android-and-ios)

#### Sharing images + text

When attempting to share images with text, some apps may fail to properly accept the share action with them.

For example, due to restrictions set up by Meta/Facebook this plugin isn't capable of sharing data reliably to Facebook related apps on Android and iOS. This includes eg. sharing text to the Facebook Messenger.

If you require this functionality please check the native Facebook Sharing SDK ([https://developers.facebook.com/docs/sharing](https://developers.facebook.com/docs/sharing)) or search for other Flutter plugins implementing this SDK. More information can be found in [this issue](https://github.com/fluttercommunity/plus_plugins/issues/413).

Other apps may also give problems when attempting to share content to them. This is because 3rd party app developers do not properly implement the logic to receive share actions.

We cannot warranty that a 3rd party app will properly implement the share functionality. Therefore, **all bugs reported regarding compatibility with a specific app will be closed.**

#### Localization in Apple platforms

It could happen that the Share sheet appears with a different language, [as reported here](https://github.com/fluttercommunity/plus_plugins/issues/2696).

To fix this issue, you will have to setup the keys `CFBundleAllowMixedLocalizations` and `CFBundleDevelopmentRegion` in your project's `info.plist`.

For more information check the [CoreFoundationKeys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html) documentation.

#### iPad

`share_plus` requires iPad users to provide the `sharePositionOrigin` parameter.

Without it, `share_plus` will not work on iPads and may cause a crash or letting the UI not responding.

To avoid that problem, provide the `sharePositionOrigin`.

For example:

    // Use Builder to get the widget context
    Builder(
      builder: (BuildContext context) {
        return ElevatedButton(
          onPressed: () => _onShare(context),
              child: const Text('Share'),
         );
      },
    ),
    
    // _onShare method:
    final box = context.findRenderObject() as RenderBox?;
    
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
      )
    );
    

copied to clipboard

See the `main.dart` in the `example` for a complete example.

Migrating from `Share.share()` to `SharePlus.instance.share()` [#](#migrating-from-shareshare-to-shareplusinstanceshare)
------------------------------------------------------------------------------------------------------------------------

The static methods `Share.share()`, `Share.shareUri()` and `Share.shareXFiles()` have been deprecated in favor of the `SharePlus.instance.share(params)`.

To convert code using `Share.share()` to the new `SharePlus` class:

1.  Wrap the current parameters in a `ShareParams` object.
2.  Change the call to `SharePlus.instance.share()`.

e.g.

    Share.share("Shared text");
    
    Share.shareUri("http://example.com");
    
    Share.shareXFiles(files);
    

copied to clipboard

Becomes:

    SharePlus.instance.share(
      ShareParams(text: "Shared text"),
    );
    
    SharePlus.instance.share(
      ShareParams(uri: "http://example.com"),
    );
    
    SharePlus.instance.share(
      ShareParams(files: files),
    );
    

copied to clipboard

Learn more [#](#learn-more)
---------------------------

*   [API Documentation](https://pub.dev/documentation/share_plus/latest/share_plus/share_plus-library.html)

[

3.69k

likes

160

points

1.48M

downloads



](/packages/share_plus/score)

### Publisher

[![verified publisher](/static/hash-9gbn097u/img/material-icon-verified.svg "Published by a pub.dev verified publisher")fluttercommunity.dev](/publishers/fluttercommunity.dev)

### Weekly Downloads

2024.06.09 - 2025.05.04

### Metadata

Flutter plugin for sharing content via the platform share UI, using the ACTION\_SEND intent on Android and UIActivityViewController on iOS.

[Homepage](https://github.com/fluttercommunity/plus_plugins)  
[Repository (GitHub)](https://github.com/fluttercommunity/plus_plugins/tree/main/packages/share_plus/share_plus)  
[View/report issues](https://github.com/fluttercommunity/plus_plugins/labels/share_plus)  

### Topics

[#share](/packages?q=topic%3Ashare) [#utils](/packages?q=topic%3Autils)

### Documentation

[API reference](/documentation/share_plus/latest/)  

### License

![](/static/hash-9gbn097u/img/material-icon-balance.svg)BSD-3-Clause ([license](/packages/share_plus/license))

### Dependencies

[cross\_file](/packages/cross_file "^0.3.4+2"), [ffi](/packages/ffi "^2.1.2"), [file](/packages/file ">=6.1.4 <8.0.0"), [flutter](https://api.flutter.dev/), [flutter\_web\_plugins](https://api.flutter.dev/flutter/flutter_web_plugins/flutter_web_plugins-library.html), [meta](/packages/meta "^1.8.0"), [mime](/packages/mime ">=1.0.4 <3.0.0"), [share\_plus\_platform\_interface](/packages/share_plus_platform_interface "^6.0.0"), [url\_launcher\_linux](/packages/url_launcher_linux "^3.1.1"), [url\_launcher\_platform\_interface](/packages/url_launcher_platform_interface "^2.3.2"), [url\_launcher\_web](/packages/url_launcher_web "^2.3.2"), [url\_launcher\_windows](/packages/url_launcher_windows "^3.1.2"), [web](/packages/web "^1.0.0"), [win32](/packages/win32 "^5.5.3")

### More

[Packages that depend on share\_plus](/packages?q=dependency%3Ashare_plus)

{"@context":"http\\u003a\\u002f\\u002fschema.org","@type":"SoftwareSourceCode","name":"share\\u005fplus","version":"11.0.0","description":"share\\u005fplus - Flutter plugin for sharing content via the platform share UI, using the ACTION\\u005fSEND intent on Android and UIActivityViewController on iOS.","url":"https\\u003a\\u002f\\u002fpub.dev\\u002fpackages\\u002fshare\\u005fplus","dateCreated":"2020-04-20T18\\u003a02\\u003a15.748611Z","dateModified":"2025-04-22T05\\u003a19\\u003a26.240981Z","programmingLanguage":"Dart","image":"https\\u003a\\u002f\\u002fpub.dev\\u002fstatic\\u002fimg\\u002fpub-dev-icon-cover-image.png","license":"https\\u003a\\u002f\\u002fpub.dev\\u002fpackages\\u002fshare\\u005fplus\\u002flicense"}
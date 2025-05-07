fvp 0.31.2 ![copy "fvp: ^0.31.2" to clipboard](/static/hash-j60jq2j3/img/content-copy-icon.svg "Copy "fvp: ^0.31.2" to clipboard")

fvp: ^0.31.2 copied to clipboard


======================================================================================================================================================================

Published 9 days ago • [![verified publisher](/static/hash-j60jq2j3/img/material-icon-verified.svg "Published by a pub.dev verified publisher")mediadevkit.com](/publishers/mediadevkit.com)Dart 3 compatible

SDK[Flutter](/packages?q=sdk%3Aflutter "Packages compatible with Flutter SDK")

Platform[Android](/packages?q=platform%3Aandroid "Packages compatible with Android platform")[iOS](/packages?q=platform%3Aios "Packages compatible with iOS platform")[Linux](/packages?q=platform%3Alinux "Packages compatible with Linux platform")[macOS](/packages?q=platform%3Amacos "Packages compatible with macOS platform")[Windows](/packages?q=platform%3Awindows "Packages compatible with Windows platform")

![liked status: inactive](/static/hash-j60jq2j3/img/like-inactive.svg)![liked status: active](/static/hash-j60jq2j3/img/like-active.svg)123

→

### Metadata

video\_player plugin and backend APIs. Support all desktop/mobile platforms with hardware decoders, optimal renders. Supports most formats via FFmpeg

More...

*   Readme
*   [Changelog](/packages/fvp/changelog)
*   [Example](/packages/fvp/example)
*   [Installing](/packages/fvp/install)
*   [Versions](/packages/fvp/versions)
*   [Scores](/packages/fvp/score)

FVP [#](#fvp)
=============

A plugin for official [Flutter Video Player](https://pub.dev/packages/video_player) to support all desktop and mobile platforms, with hardware accelerated decoding and optimal rendering. Based on [libmdk](https://github.com/wang-bin/mdk-sdk). You can also create your own players other than official `video_player` with [backend player api](#backend-player-api)

Prebuilt example can be download from artifacts of [github actions](https://github.com/wang-bin/fvp/actions).

[More examples are here](https://github.com/wang-bin/mdk-examples/tree/master/flutter)

project is create with `flutter create -t plugin --platforms=linux,macos,windows,android,ios -i objc -a java fvp`

Features [#](#features)
-----------------------

*   All platforms: Windows x64(including win7) and arm64, Linux x64 and arm64, macOS, iOS, Android(requires flutter > 3.19 because of minSdk 21).
*   You can choose official implementation or this plugin's
*   Optimal render api: d3d11 for windows, metal for macOS/iOS, OpenGL for Linux and Android(Impeller support)
*   Hardware decoders are enabled by default
*   Dolby Vision support on all platforms
*   Minimal code change for existing [Video Player](https://pub.dev/packages/video_player) apps
*   Support most formats via FFmpeg demuxer and software decoders if not supported by gpu. You can use your own ffmpeg 4.0~7.1(or master branch) by removing bundled ffmpeg dynamic library.
*   High performance. Lower cpu, gpu and memory load than libmpv based players.
*   Support audio without video
*   HEVC, VP8 and VP9 transparent video
*   Small footprint. Only about 10MB size increase per cpu architecture(platform dependent).

How to Use [#](#how-to-use)
---------------------------

*   Add [fvp](https://pub.dev/packages/fvp) in your pubspec.yaml dependencies: `flutter pub add fvp`. Since flutter 3.27, fvp must be a direct dependency in your app's pubspec.yaml.
*   **(Optional)** Add 2 lines in your video\_player examples. Without this step, this plugin will be used for video\_player unsupported platforms(windows, linux), official implementation will be used otherwise.

    import 'package:fvp/fvp.dart' as fvp;
    
    fvp.registerWith(); // in main() or anywhere before creating a player. use fvp for all platforms.
    

copied to clipboard

You can also select the platforms to enable fvp implementation

    registerWith(options: {'platforms': ['windows', 'macos', 'linux']}); // only these platforms will use this plugin implementation
    

copied to clipboard

To select [other decoders](https://github.com/wang-bin/mdk-sdk/wiki/Decoders), pass options like this

    fvp.registerWith(options: {
        'video.decoders': ['D3D11', 'NVDEC', 'FFmpeg']
        //'lowLatency': 1, // optional for network streams
        }); // windows
    

copied to clipboard

[The document](https://pub.dev/documentation/fvp/latest/fvp/registerWith.html) lists all options for `registerWith()`

### Error Handling [#](#error-handling)

Errors are usually produced when loading a media.

    _controller.addListener(() {
      if (_controller.value.hasError && !_controller.value.isCompleted) {
        ...
    

copied to clipboard

### Backend Player API [#](#backend-player-api)

    import 'package:fvp/mdk.dart';
    

copied to clipboard

The plugin implements [VideoPlayerPlatform](https://pub.dev/packages/video_player_platform_interface) via [a thin wrapper](https://github.com/wang-bin/fvp/blob/master/lib/video_player_mdk.dart) on [player.dart](https://github.com/wang-bin/fvp/blob/master/lib/src/player.dart).

Now we also expose this backend player api so you can create your own players easily, and gain more features than official [video\_player](https://pub.dev/packages/video_player), for example, play from a given position, loop in a range, decoder selection, media information detail etc. You can also reuse the Player instance without unconditionally create and dispose, changing the `Player.media` is enough. [This is an example](https://github.com/wang-bin/mdk-examples/blob/master/flutter/simple/lib/multi_textures.dart)

### VideoPlayerController Extensions [#](#videoplayercontroller-extensions)

With this extension, we can leverage mature `video_player` code without rewriting a new one via backend player api, but gain more features, for example `snapshot()`, `record()`, `fastSeekTo()`, `setExternalSubtitle()`.

    import 'package:fvp/fvp.dart' as fvp;
    
    fvp.registerWith(); // in main() or anywhere before creating a player. use fvp for all platforms.
    
    // somewhere after controller is initialized
    _controller.record('rtmp://127.0.0.1/live/test');
    

copied to clipboard

Upgrade Dependencies Manually [#](#upgrade-dependencies-manually)
=================================================================

Upgrading binary dependencies can bring new features and backend bug fixes. For macOS and iOS, in your project dir, run

    pod cache clean mdk
    find . -name Podfile.lock -delete
    rm -rf {mac,i}os/Pods
    

copied to clipboard

For other platforms, set environment var `FVP_DEPS_LATEST=1` and rebuilt, will upgrade to the latest sdk. If fvp is installed from pub.dev, run `flutter pub cache clean` is another option.

Design [#](#design)
===================

*   Playback control api in dart via ffi
*   Manage video renderers in platform specific manners. Receive player ptr via `MethodChannel` to construct player instance and set a renderer target.
*   Callbacks and events in C++ are notified by ReceivePort
*   Function with a one time callback is async and returns a future

Enable Subtitles [#](#enable-subtitles)
=======================================

libass is required, and it's added to your app automatically for windows, macOS and android(remove ass.dll, libass.dylib and libass.so from mdk-sdk if you don't need it). For iOS, [download](https://sourceforge.net/projects/mdk-sdk/files/deps/dep.7z/download) and add `ass.framework` to your xcode project. For linux, system libass can be used, you may have to install manually via system package manager.

If required subtitle font is not found in the system(e.g. android), you can add [assets/subfont.ttf](https://github.com/mpv-android/mpv-android/raw/master/app/src/main/assets/subfont.ttf) in pubspec.yaml assets as the fallback. Optionally you can also download the font file by fvp like this

      fvp.registerWith(options: {
        'subtitleFontFile': 'https://github.com/mpv-android/mpv-android/raw/master/app/src/main/assets/subfont.ttf'
      });
    

copied to clipboard

DO NOT use flutter-snap [#](#do-not-use-flutter-snap)
=====================================================

Flutter can be installed by snap, but it will add some [enviroment vars(`CPLUS_INCLUDE_PATH` and `LIBRARY_PATH`) which may break C++ compiler](https://github.com/canonical/flutter-snap/blob/main/env.sh#L15-L18). It's not recommended to use snap, althrough building for linux is [fixed](https://github.com/wang-bin/fvp/commit/567c68270ba16b95b1198ae58850707ae4ad7b22), but it's not possible for android.

Screenshots [#](#screenshots)
=============================

![fpv_android](https://user-images.githubusercontent.com/785206/248862591-40f458e5-d7ca-4513-b709-b056deaaf421.jpeg) ![fvp_ios](https://user-images.githubusercontent.com/785206/250348936-e5e1fb14-9c81-4652-8f53-37e8d64195a3.jpg) ![fvp_win](https://user-images.githubusercontent.com/785206/248859525-920bdd51-6947-4a00-87b4-9c1a21a68d51.jpeg) ![fvp_win7](https://user-images.githubusercontent.com/785206/266754957-883d05c9-a057-4c1c-b824-0dc385a13f78.jpg) ![fvp_linux](https://user-images.githubusercontent.com/785206/248859533-ce2ad50b-2ead-43bb-bf25-6e2575c5ebe1.jpeg) ![fvp_macos](https://user-images.githubusercontent.com/785206/248859538-71de39a4-c5f0-4c8f-9920-d7dfc6cd0d9a.jpg)

[

123

likes

150

points

4.48k

downloads



](/packages/fvp/score)

### Publisher

[![verified publisher](/static/hash-j60jq2j3/img/material-icon-verified.svg "Published by a pub.dev verified publisher")mediadevkit.com](/publishers/mediadevkit.com)

### Weekly Downloads

2024.10.07 - 2025.04.21

### Metadata

video\_player plugin and backend APIs. Support all desktop/mobile platforms with hardware decoders, optimal renders. Supports most formats via FFmpeg

[Repository (GitHub)](https://github.com/wang-bin/fvp)  

### Topics

[#video](/packages?q=topic%3Avideo) [#player](/packages?q=topic%3Aplayer) [#video-player](/packages?q=topic%3Avideo-player) [#audio-player](/packages?q=topic%3Aaudio-player) [#videoplayer](/packages?q=topic%3Avideoplayer)

### Documentation

[API reference](/documentation/fvp/latest/)  

### License

![](/static/hash-j60jq2j3/img/material-icon-balance.svg)BSD-3-Clause ([license](/packages/fvp/license))

### Dependencies

[ffi](/packages/ffi "^2.1.0"), [flutter](https://api.flutter.dev/), [http](/packages/http "^1.0.0"), [logging](/packages/logging "^1.2.0"), [path](/packages/path "^1.8.0"), [path\_provider](/packages/path_provider "^2.1.2"), [plugin\_platform\_interface](/packages/plugin_platform_interface "^2.0.0"), [video\_player](/packages/video_player "^2.6.0"), [video\_player\_platform\_interface](/packages/video_player_platform_interface "^6.2.0")

### More

[Packages that depend on fvp](/packages?q=dependency%3Afvp)

{"@context":"http\\u003a\\u002f\\u002fschema.org","@type":"SoftwareSourceCode","name":"fvp","version":"0.31.2","description":"fvp - video\\u005fplayer plugin and backend APIs. Support all desktop\\u002fmobile platforms with hardware decoders, optimal renders. Supports most formats via FFmpeg","url":"https\\u003a\\u002f\\u002fpub.dev\\u002fpackages\\u002ffvp","dateCreated":"2023-06-26T16\\u003a23\\u003a33.605901Z","dateModified":"2025-04-14T04\\u003a14\\u003a34.630262Z","programmingLanguage":"Dart","image":"https\\u003a\\u002f\\u002fpub.dev\\u002fstatic\\u002fimg\\u002fpub-dev-icon-cover-image.png","license":"https\\u003a\\u002f\\u002fpub.dev\\u002fpackages\\u002ffvp\\u002flicense"}
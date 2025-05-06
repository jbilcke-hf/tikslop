# WebSocket Services Fix Guide

This document provides guidance on how to fix the WebSocket services implementation in the codebase to resolve the compilation errors.

## Issues Identified

1. The mixin classes (`WebSocketChatService`, `WebSocketSearchService`, `WebSocketContentGenerationService`, `WebSocketConnectionService`) access fields and methods from the `WebSocketCoreService` base class that are not actually available through the mixin mechanism.

2. The `ClipQueueManager` had a duplicate `activeGenerations` property.

3. The `VideoPlaybackController` was using a private field `_activeGenerations` from `ClipQueueManager`.

## Changes Made

1. Fixed duplicate `activeGenerations` in `ClipQueueManager`:
   - Renamed the int getter to `activeGenerationsCount`
   - Added a `Set<String> get activeGenerations` getter to expose the private field

2. Updated `printQueueState` in `ClipQueueStats` to accept dynamic type for the `activeGenerations` parameter.

3. Fixed imports for WebSocketCoreService in all mixin files.

4. Updated VideoPlaybackController to use the public getter for activeGenerations.

## Remaining Issues

The main issue is with the mixin inheritance. Mixins in Dart can only access methods and fields they declare themselves or that are available in the class they are applied to. Mixins don't have visibility into private fields of the class they're "on".

### Option 1: Refactor to use composition instead of mixins

Instead of using mixins, refactor to use composition:

```dart
class WebSocketApiService {
  final ChatService _chatService;
  final SearchService _searchService;
  final ConnectionService _connectionService;
  final ContentGenerationService _contentGenerationService;
  
  WebSocketApiService() :
    _chatService = ChatService(),
    _searchService = SearchService(),
    _connectionService = ConnectionService(),
    _contentGenerationService = ContentGenerationService();
    
  // Forward methods to the appropriate service
}
```

### Option 2: Make private fields protected

Make the necessary fields and methods protected (rename from `_fieldName` to `fieldName` or create protected getters/setters).

### Option 3: Implement the WebSocketCore interface in each mixin

Define an interface that all the mixins implement, rather than using "on WebSocketCoreService":

```dart
abstract class WebSocketCoreInterface {
  bool get isConnected;
  bool get isInMaintenance;
  ConnectionStatus get status;
  // Add all methods and properties needed by the mixins
}

class WebSocketCoreService implements WebSocketCoreInterface {
  // Implementation
}

mixin WebSocketChatService implements WebSocketCoreInterface {
  // Implementation that uses the interface methods
}
```

## Steps to Fix

1. Define a shared interface/abstract class that includes all the methods and properties needed by the mixins
2. Update WebSocketCoreService to implement this interface
3. Update all mixins to implement this interface rather than using "on WebSocketCoreService"
4. In the final WebSocketApiService class, implement the interface and have it delegate to the core service

## For Now

As a temporary solution, a simplified version of main.dart has been created that forces the app into maintenance mode, bypassing the WebSocket initialization and connection issues.
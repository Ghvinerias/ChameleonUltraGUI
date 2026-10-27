# `wear_sync`: Wear OS Data Layer transport (Track T5)

Plugin: `chameleonultragui/packages/wear_sync` (Android only, Kotlin over
`com.google.android.gms:play-services-wearable:19.0.0`).
Dart transport: `lib/sync/wear_data_layer_transport.dart` (`WearDataLayerTransport implements SyncTransport`).

## 1. Decision: own plugin, not `watch_connectivity`

Evaluated `watch_connectivity` 0.2.11 (published 2026-10-19, BSD-3-Clause, GPL-3.0 compatible; actively released: 0.2.7 to 0.2.11 between Feb and Oct 2026; wraps WatchConnectivity on iOS and Wearable APIs on Android).
Its Android code (`WatchConnectivityPlugin.kt`) only uses `MessageClient.sendMessage` (to all nodes, on a single path), `DataClient.putDataItem` (an "application context" map) and node queries. Evidence from the source:

| Need | `watch_connectivity` | Own plugin |
|---|---|---|
| Messages with size limit exposed | message only, no size check or limit | yes (`maxMessageBytes`) |
| Multi-MB payloads | no `ChannelClient`, no `Asset`; DataItems cap at ~100 KB | `ChannelClient` stream |
| Byte progress, cancel, link-loss detection | none | yes |
| Capability advertisement / peer app discovery | none (node list only) | `CapabilityClient` |
| Play Services missing | not handled | reports `unavailable` |
| Extra deps | iOS plumbing, platform interface package | none |

It does not cover bulk transfer or cancellation, so per the track's rule we wrote our own (~400 lines Kotlin). The package is not added.

### Why `ChannelClient` for bulk (not `Asset`/`DataClient`)
DataClient assets are content-addressed, synced state: no progress, no cancel, items persist and sync even when nobody listens, and receiving needs a listener on a changed item plus explicit cleanup. Our transfers are one-shot, need byte progress, cancel from either side and loss detection. A `ChannelClient` stream gives exactly that with ordered, reliable delivery while the channel lives.

## 2. How the sides find each other
* Both builds share the application id and dev signing key (Data Layer requirement).
* The plugin ships `res/values/wear_sync_capabilities.xml` declaring the static capability `chameleon_ultra_sync` (`android_wear_capabilities`); it is merged into the phone and the watch apps. Each side queries `CapabilityClient.getCapability(..., FILTER_REACHABLE)` and registers a listener, so the peer is "the reachable node whose app advertises the capability" (nearby nodes preferred). No peer app installed means `available = false`.
* Messages go to path `/chameleon/sync/msg`; each bulk transfer opens a channel at `/chameleon/sync/bulk/<transferId>`.
* Messages and channels are only received while the app process is running with the event stream listened to (no `WearableListenerService`; the watch UI must be running or a foreground flow). Wake-up on incoming data is out of scope.

## 3. API

MethodChannel `io.chameleon.ultra/wear_sync`:

| Method | Args | Result / errors |
|---|---|---|
| `getStatus` | | `{available, reason?, maxMessageBytes}` (`available=false` without Play Services) |
| `getPeer` | | `{id, name, nearby}` or null |
| `sendMessage` | `bytes` | errors `too_large`, `no_peer`, `unavailable`, `failed` |
| `openBulk` | `transferId`, `header` (opaque bytes) | opens channel, writes header frame |
| `sendChunk` | `transferId`, `index`, `bytes` | `no_transfer`, `link_lost` |
| `endBulk` | `transferId` | writes END frame |
| `cancelBulk` | `transferId` | closes the channel with app code 7; unknown id is a no-op |

EventChannel `io.chameleon.ultra/wear_sync/events` (single stream; first listen starts native listeners and emits the current peer, cancel removes listeners and closes open channels). Events are maps with `event` =
`peer {available,id,name,nearby}`, `message {bytes}`, `incomingBulk {transferId, header}`, `chunk {transferId,index,bytes}`, `bulkEnd {transferId}`, `bulkAborted {transferId, reason: cancelledByPeer|linkLost|error}`.

Dart: `WearSyncPlatform` (abstract, injectable) and `MethodChannelWearSync`. Frame format per channel: `int32 index | int32 length | payload`, first frame index `-1` = header, `-2` = END. Receiver closes the channel after END; sender closes after 30 s if the receiver does not.

`WearDataLayerTransport.create({platform, preferredChunkSize = 32 KiB})` returns a transport that is `PeerState.unavailable` forever when `isSupported` is false (no exceptions). Messages are JSON; `maxMessageBytes` = 100 KiB. Bulk progress is computed in Dart (distinct chunk indices). Any `WearSyncException` is mapped to `SyncTransportException`; use after an abort throws `StateError`.

## 4. Gradle / Play Services requirement
* The phone APK now links `play-services-wearable` (about its AAR plus `play-services-base`/`basement`). The plugin checks `GoogleApiAvailability` at runtime and catches linkage/`ApiException(API_UNAVAILABLE)`, so phones without Play Services report "sync unavailable" and do not crash. Not verified on a de-Googled device.
* compileSdk 36 / AGP 8.13 / Kotlin 2.4.20 compile; coexists with Kadb from `adb_wifi`.

## 5. Verified vs not
Verified: `flutter build apk --flavor phone` and `--flavor wear -t lib/wear/main_wear.dart` compile with the plugin linked (plugin classes and capability name present in the wear dex); `./gradlew :wear_sync:testDebugUnitTest` (6 JUnit tests: framing round trip, truncation, bad length, abort mapping); `flutter test test/sync/wear_data_layer_transport_test.dart` (10 tests, fake platform).
NOT verified: anything on real devices or emulators (capability discovery, MessageClient, ChannelClient, close reasons, behaviour without GMS).

## 6. Manual two-device test (real phone + watch)
Preconditions: phone and watch paired via the Wear OS app, both running dev builds of this branch (`io.chameleon.ultra.dev`, same dev keystore), `adb logcat` on both.
1. Start the app on both; call `WearDataLayerTransport.create()` on each. Expect `isSupported == true` and `peerState` to reach `available` on both within a few seconds. Force-stop one app: the other should go `unavailable` (capability change; may take seconds). Note whether it does.
2. `sendMessage` both directions with a small `SyncMessage`; expect it on `messages`. Send >100 KiB: expect `SyncTransportException`.
3. Bulk: `openBulk` with 1 MB, then 5 MB, chunks of 32 KiB; receiver should get `incomingBulk`, ordered chunks, progress to 100%, chunks stream closes after `end()`. Record throughput.
4. Cancel from sender mid-way: receiver `aborted == cancelledByPeer`. Cancel from receiver: sender's next `sendChunk` throws `StateError`.
5. Link loss: switch off phone Bluetooth/airplane mode mid-transfer: expect `linkLost` (or `error`; record which `closeReason` appeared, it is the least certain mapping, see `AbortDecider`).
6. Install the phone build on a phone without Play Services (or with GMS disabled): app must not crash; `isSupported == false`.
7. Reopen the app on the watch while the phone transfers: the transfer is lost (no background listener); confirm expectation.

## 7. Limitations / open questions
* No store-and-forward: both apps must be running; no `WearableListenerService`.
* Transfer abort reasons rely on `ChannelClient` close codes (`AbortDecider`), unverified on hardware; a 1.5 s fallback emits `linkLost` if the close callback never arrives.
* One peer only (nearby preferred). `FILTER_REACHABLE` includes cloud-relayed nodes, so `available` can be true over Wi-Fi/LTE bridge; throughput differs.
* Chunk events cross the platform channel with no backpressure from Dart to the receiver.

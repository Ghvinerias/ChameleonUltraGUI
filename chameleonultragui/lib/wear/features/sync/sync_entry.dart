import 'package:chameleonultragui/wear/navigation/wear_destinations.dart';
import 'package:flutter/widgets.dart';

/// Entry point of the "Sync" destination. The track that owns this
/// folder replaces the body with the real screen; everything else about the
/// feature lives in this folder.
Widget syncEntry(BuildContext context) =>
    const ComingSoonPage(id: WearDestinationId.sync);

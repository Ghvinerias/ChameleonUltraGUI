import 'package:chameleonultragui/wear/navigation/wear_destinations.dart';
import 'package:flutter/widgets.dart';

/// Entry point of the "Dictionaries" destination. The track that owns this
/// folder replaces the body with the real screen; everything else about the
/// feature lives in this folder.
Widget dictionariesEntry(BuildContext context) =>
    const ComingSoonPage(id: WearDestinationId.dictionaries);

// Keep upstream insertion points stable while provider UI evolves independently.
export 'package:immich_mobile/embedded_network/embedded_network_settings.dart'
    show EmbeddedNetworkSettings;
import 'package:flutter/widgets.dart';
import 'package:immich_mobile/embedded_network/embedded_network_settings.dart';

class TailnetSettings extends StatelessWidget {
  const TailnetSettings({super.key});
  @override
  Widget build(BuildContext context) => const EmbeddedNetworkSettings();
}

import 'package:flutter/material.dart';
import 'package:immich_mobile/tailnet/tailnet_session.dart';

class TailnetBackupNotice extends StatelessWidget {
  const TailnetBackupNotice({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: TailnetSession.enabled,
    builder: (context, snapshot) => snapshot.data != true
        ? const SizedBox.shrink()
        : const Card(
            child: ListTile(
              leading: Icon(Icons.pause_circle_outline),
              title: Text('Tailscale：后台自动备份已暂停'),
              subtitle: Text(
                '保持 Immich 在前台可继续备份。离开 App 会暂停；重新打开后按原有备份设置继续。下载原图也需要保持前台。',
              ),
            ),
          ),
  );
}

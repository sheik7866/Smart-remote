import 'package:material_ui/material_ui.dart';

import 'features/home/home_screen.dart';
import 'theme/remote_theme.dart';

/// App root. Deliberately thin: state and protocol wiring arrive with M2/M3,
/// and the UI must never import `package:webos_ssap` directly.
class SmartRemoteApp extends StatelessWidget {
  const SmartRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Remote',
      debugShowCheckedModeBanner: false,
      theme: buildRemoteTheme(),
      home: const HomeScreen(),
    );
  }
}

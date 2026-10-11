import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStorage.init();
  runApp(const ScribbledAngelStudioApp());
}

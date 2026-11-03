import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'state/sqlite_repository.dart';
import 'theme.dart';
import 'ui/shell/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final repo = SqliteRepository();

  runApp(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: const ClosetApp(),
    ),
  );
}

class ClosetApp extends ConsumerWidget {
  const ClosetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: '明天穿什么',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const _Boot(),
    );
  }
}

/// 启动闸门。建库失败时把错误显示出来，而不是一直转圈。
class _Boot extends ConsumerWidget {
  const _Boot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootstrapProvider);

    return boot.when(
      loading: () => const Scaffold(
        body: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, st) => Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 30, color: AppColors.ink3),
                const SizedBox(height: 14),
                const Text('打不开衣橱数据',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text('$e', style: AppTheme.hint, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                SizedBox(
                  width: 180,
                  child: FilledButton(
                    onPressed: () => ref.invalidate(bootstrapProvider),
                    child: const Text('再试一次'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (_) => const HomeShell(),
    );
  }
}

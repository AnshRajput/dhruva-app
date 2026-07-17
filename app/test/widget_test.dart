// App-shell smoke test: `/models` is home (T5), `/debug-chat` (Loop-2 debug
// harness) stays reachable via the app bar.

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/hf_api/hf_api_client.dart';
import 'package:dhruva/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('models hub is the app home', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hfApiClientProvider.overrideWithValue(
            HfApiClient(
              client: MockClient((request) async => http.Response('[]', 200)),
            ),
          ),
          deviceInfoServiceProvider.overrideWithValue(
            const FakeDeviceInfoService(
              memory: DeviceMemoryInfo(
                totalBytes: 8000000000,
                availableBytes: 4000000000,
              ),
              storage: DeviceStorageInfo(
                totalBytes: 64000000000,
                freeBytes: 32000000000,
              ),
            ),
          ),
        ],
        child: const DhruvaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Models'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
  });

  testWidgets('debug chat screen is reachable from the app bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hfApiClientProvider.overrideWithValue(
            HfApiClient(
              client: MockClient((request) async => http.Response('[]', 200)),
            ),
          ),
          deviceInfoServiceProvider.overrideWithValue(
            const FakeDeviceInfoService(
              memory: DeviceMemoryInfo(
                totalBytes: 8000000000,
                availableBytes: 4000000000,
              ),
              storage: DeviceStorageInfo(
                totalBytes: 64000000000,
                freeBytes: 32000000000,
              ),
            ),
          ),
        ],
        child: const DhruvaApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Engine debug'));
    await tester.pumpAndSettle();

    expect(find.text('Dhruva · Engine Debug'), findsOneWidget);
  });
}

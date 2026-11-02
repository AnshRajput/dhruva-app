import 'package:dhruva/core/notifications/morning_brief.dart';

class FakeGateway implements NotificationGateway {
  FakeGateway({this.permitted = true});
  bool permitted;
  int permissionRequests = 0;
  bool initialised = false;
  String? launch;
  void Function(String? payload)? tap;
  final cancelled = <int>[];
  final scheduled =
      <({int id, DateTime when, String title, String body, String payload})>[];

  @override
  Future<void> init(void Function(String? payload) onTap) async {
    initialised = true;
    tap = onTap;
  }

  @override
  Future<String?> launchPayload() async => launch;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permitted;
  }

  @override
  Future<bool> isPermitted() async => permitted;

  @override
  Future<void> cancelAll(Iterable<int> ids) async => cancelled.addAll(ids);

  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required String payload,
  }) async => scheduled.add((
    id: id,
    when: when,
    title: title,
    body: body,
    payload: payload,
  ));
}

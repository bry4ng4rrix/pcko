import '../lib/shared/util/network_util.dart';

void main() async {
  final ms = await measurePingMs();
  print('ping=$ms ms');
}

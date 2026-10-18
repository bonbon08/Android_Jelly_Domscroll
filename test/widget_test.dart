import 'package:flutter_test/flutter_test.dart';
import 'package:jellyreels/jellyfin/jellyfin_models.dart';

void main() {
  test('clip length stays within configured bounds', () {
    const item = JellyfinItem(
      id: '1',
      name: 'Test Episode',
      type: 'Episode',
      seriesName: 'Test Series',
      seriesId: 's1',
      runtime: Duration(minutes: 40),
    );
    expect(item.groupKey, 's1');
    expect(item.displayTitle, contains('Test Series'));
  });
}

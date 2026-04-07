import 'package:flutter_test/flutter_test.dart';
import 'package:careway/models/parent_profile.dart';

void main() {
  test('ParentProfile JSON round-trip preserves fields', () {
    const profile = ParentProfile(
      id: 'p1',
      userId: 'u1',
      name: '홍길동',
      birthYear: 1950,
      region: '서울특별시',
      subRegion: '강남구',
      healthStatus: 'fair',
      hasLtcGrade: true,
      ltcGrade: 3,
      incomeLevel: 4,
      isBasicRecipient: true,
      liveAlone: false,
    );

    final map = profile.toJson();
    final restored = ParentProfile.fromJson({
      'id': 'p1',
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
      ...map,
    });

    expect(restored.id, 'p1');
    expect(restored.userId, profile.userId);
    expect(restored.name, profile.name);
    expect(restored.birthYear, profile.birthYear);
    expect(restored.region, profile.region);
    expect(restored.subRegion, profile.subRegion);
    expect(restored.healthStatus, profile.healthStatus);
    expect(restored.hasLtcGrade, profile.hasLtcGrade);
    expect(restored.ltcGrade, profile.ltcGrade);
    expect(restored.incomeLevel, profile.incomeLevel);
    expect(restored.isBasicRecipient, profile.isBasicRecipient);
    expect(restored.liveAlone, profile.liveAlone);
  });
}

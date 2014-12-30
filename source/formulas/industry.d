import std.math;

ulong calculateMaterials(int runs, ulong baseQuantity, int ME = 0, float facility = 1.0) {
  auto tmp = cast(int) round(runs * baseQuantity * facility * (100 - ME));
  auto result = tmp / 100;
  auto remainder = tmp % 100;
  if (remainder > 0) {
    result++;
  }

  return runs > result ? runs : result;
}

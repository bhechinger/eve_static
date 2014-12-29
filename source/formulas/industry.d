import std.math;

//auto num = 3.04999999;
//auto x = cast(int) round(num * 100);
//auto y = x / 100;
//auto z = x % 100;
//writeln("x = ", x);
//writeln("y = ", y);
//writeln("z = ", z);
//if (z > 0) {
//  y++;
//}
//writeln("y = ", y);

double calculateMaterialModifier(int ME = 0, float facility = 1.0, float team1 = 1.0, float team2 = 1.0) {
  auto realME = (100 - ME)/100;
  return realME * facility * team1 * team2;
}

real calculateMaterials(int runs, ulong baseQuantity, double materialModifier) {
  return fmax(runs, ceil(round(runs * baseQuantity * materialModifier)));
}

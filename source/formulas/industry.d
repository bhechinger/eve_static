import std.math;

double calculateMaterialModifier(int ME = 0, float facility = 1.0, float team1 = 1.0, float team2 = 1.0) {
  auto realME = (100 - ME)/100;
  return(realME * facility * team1 * team2);
}

ulong calculateMaterials(int runs, ulong baseQuantity, double materialModifier) {
  //return(max(runs, ceil(round(runs ∗ baseQuantity ∗ materialModifier, 2));
  return(0);
}

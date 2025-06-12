import 'package:flutter/foundation.dart';

class Wallet extends ChangeNotifier {
  double _credit = 0;

  double get credit => _credit;

  void addCredit(double amount) {
    _credit += amount;
    notifyListeners();
  }

  bool spendCredit(double amount) {
    if (_credit >= amount) {
      _credit -= amount;
      notifyListeners();
      return true;
    }
    return false;
  }

  void subtractCredit(double amount) {}
}

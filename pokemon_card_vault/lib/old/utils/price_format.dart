String formatPknAmount(num amount, {int decimals = 2}) {
  var formattedAmount = amount.toStringAsFixed(decimals);
  if (formattedAmount.contains('.')) {
    formattedAmount = formattedAmount.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  return formattedAmount;
}

String formatPkn(num amount, {int decimals = 2}) {
  return '${formatPknAmount(amount, decimals: decimals)} PKN';
}

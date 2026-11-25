/// Date windows for the inventory reports. These are local calendar dates in
/// yyyy-MM-dd form, sent as the `from` and `to` query values.
library;

import '../data/json_read.dart';

/// Today as yyyy-MM-dd.
String todayWire([DateTime? now]) => wireDay(now ?? DateTime.now());

/// The date [days] days before today, as yyyy-MM-dd.
String daysAgoWire(int days, [DateTime? now]) =>
    wireDay((now ?? DateTime.now()).subtract(Duration(days: days)));

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Short day text as on the boards: "23 Nov". Null gives an empty string.
String shortDay(DateTime? d) => d == null ? '' : '${d.day} ${_months[d.month - 1]}';

extension DurationExt on int {
  Duration get milli => Duration(milliseconds: this);
  Duration get sec => Duration(seconds: this);
  Duration get hour => Duration(hours: this);
  Duration get mimute => Duration(minutes: this);
  Duration get years => Duration(days: this);
}

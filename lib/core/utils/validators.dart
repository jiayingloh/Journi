class Validators {
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    return null;
  }
}

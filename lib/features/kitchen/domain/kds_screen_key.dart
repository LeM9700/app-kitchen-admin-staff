/// Builds a unique, deterministic screen key from a user-provided screen name.
///
/// Converts the screen name into a URL-safe slug suitable for use as the backend's
/// `screen_key` field. The transformation is deterministic and consistent for any
/// given input name, ensuring that the same name always produces the same key.
String buildKdsScreenKey(String name) {
  if (name.isEmpty) {
    // Fallback when input is empty or becomes empty after filtering.
    return 'ecran';
  }

  // Step 1: Normalize accents to their base characters (basic Latin transliteration)
  String normalized = _removeAccents(name);

  // Step 2: Convert to lowercase
  String lowercase = normalized.toLowerCase();

  // Step 3: Replace sequences of spaces (and other whitespace) with a single dash
  String withDashes = lowercase.replaceAll(RegExp(r'\s+'), '-');

  // Step 4: Keep only allowed characters: a-z, 0-9, underscore, dash
  String filtered = withDashes.replaceAll(RegExp(r'[^a-z0-9_\-]'), '');

  // Step 5: Trim leading and trailing dashes
  String trimmed = filtered.replaceAll(RegExp(r'^-+|-+$'), '');

  // Step 6: Truncate to maximum 64 characters, then re-trim trailing dashes
  String truncated = trimmed.length > 64 ? trimmed.substring(0, 64) : trimmed;
  truncated = truncated.replaceAll(RegExp(r'-+$'), '');

  // Step 7: If the result is empty, return the fallback
  // Fallback is deterministic and non-random to ensure screen_key uniqueness is a user concern.
  return truncated.isEmpty ? 'ecran' : truncated;
}

/// Removes accents from Latin characters using a basic mapping.
String _removeAccents(String input) {
  const Map<String, String> accentMap = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'ã': 'a',
    'å': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ç': 'c',
    'ñ': 'n',
  };

  String result = input;
  accentMap.forEach((accented, base) {
    result = result.replaceAll(accented, base);
    result = result.replaceAll(accented.toUpperCase(), base);
  });
  return result;
}

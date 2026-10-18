/// Merging "I have read these" ids into the stored list.
///
/// Existing ids keep their order, new ones are appended, and the oldest fall
/// off beyond [cap] (they are old enough to have left the centre's window).
List<String> mergeReadIds(
  Iterable<String> current,
  Iterable<String> added, {
  int cap = 500,
}) {
  final seen = <String>{};
  final merged = <String>[
    for (final id in [...current, ...added])
      if (seen.add(id)) id,
  ];
  return merged.length > cap ? merged.sublist(merged.length - cap) : merged;
}

import '../data/pos_models.dart';

/// Min/max rules for modifier groups, kept pure so the sheet and the tests use
/// the same code. Server-side MODIFIER_RULES still applies.

/// Error text per group id. Empty map means the selection is valid.
Map<String, String> modifierErrors(
  List<PosModifierGroup> groups,
  Set<String> selectedOptionIds,
) {
  final errors = <String, String>{};
  for (final group in groups) {
    final count = group.options.where((o) => selectedOptionIds.contains(o.id)).length;
    if (count < group.minSelect) {
      errors[group.id] = group.minSelect == 1
          ? 'Pick one for ${group.name}'
          : 'Pick at least ${group.minSelect} for ${group.name}';
    } else if (count > group.maxSelect) {
      errors[group.id] = group.maxSelect == 1
          ? 'Pick only one for ${group.name}'
          : 'Pick up to ${group.maxSelect} for ${group.name}';
    }
  }
  return errors;
}

bool isModifierSelectionValid(List<PosModifierGroup> groups, Set<String> selectedOptionIds) =>
    modifierErrors(groups, selectedOptionIds).isEmpty;

/// Applies one tap on an option. A single-choice group swaps the option in.
/// A multi-choice group ignores a tap that would go over the max.
Set<String> toggleModifierOption(
  PosModifierGroup group,
  Set<String> selectedOptionIds,
  String optionId,
) {
  final next = {...selectedOptionIds};
  final groupOptionIds = {for (final o in group.options) o.id};
  if (next.contains(optionId)) {
    next.remove(optionId);
    return next;
  }
  if (group.isSingleChoice) {
    next.removeWhere(groupOptionIds.contains);
    next.add(optionId);
    return next;
  }
  final chosen = next.where(groupOptionIds.contains).length;
  if (chosen < group.maxSelect) next.add(optionId);
  return next;
}

/// Sum of the price deltas of the selected options, in rupees.
num modifierDelta(List<PosModifierGroup> groups, Set<String> selectedOptionIds) {
  num total = 0;
  for (final group in groups) {
    for (final option in group.options) {
      if (selectedOptionIds.contains(option.id)) total += option.priceDeltaValue;
    }
  }
  return total;
}

List<List<T>> paginateKitchenItems<T>(
  List<T> items, {
  int perPage = 4,
}) {
  _validatePerPage(perPage);

  final pages = <List<T>>[];
  for (var start = 0; start < items.length; start += perPage) {
    var end = start + perPage;
    if (end > items.length) {
      end = items.length;
    }
    pages.add(items.sublist(start, end));
  }

  return pages;
}

int remainingKitchenItems({
  required int totalItems,
  required int currentPage,
  int perPage = 4,
}) {
  _validatePerPage(perPage);
  if (totalItems < 0) {
    throw ArgumentError.value(
      totalItems,
      'totalItems',
      'must not be negative',
    );
  }
  if (currentPage < 0) {
    throw ArgumentError.value(
      currentPage,
      'currentPage',
      'must not be negative',
    );
  }

  final consumedItems = (currentPage + 1) * perPage;
  if (consumedItems >= totalItems) {
    return 0;
  }

  return totalItems - consumedItems;
}

void _validatePerPage(int perPage) {
  if (perPage <= 0) {
    throw ArgumentError.value(
      perPage,
      'perPage',
      'must be greater than zero',
    );
  }
}

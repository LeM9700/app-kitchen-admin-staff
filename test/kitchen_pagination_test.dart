import 'package:app_admin_staff/features/kitchen/application/kitchen_pagination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns no page for empty input', () {
    expect(paginateKitchenItems<int>(const []), isEmpty);
  });

  test('keeps four items on one page', () {
    final pages = paginateKitchenItems([1, 2, 3, 4]);

    expect(pages.length, 1);
    expect(pages.single, [1, 2, 3, 4]);
  });

  test('splits five items into pages of four and one', () {
    final pages = paginateKitchenItems([1, 2, 3, 4, 5]);

    expect(pages.map((page) => page.length), [4, 1]);
  });

  test('splits thirteen items into four pages', () {
    final pages =
        paginateKitchenItems(List<int>.generate(13, (index) => index));

    expect(pages.map((page) => page.length), [4, 4, 4, 1]);
  });

  test('does not mutate the source list', () {
    final source = [1, 2, 3, 4, 5];

    paginateKitchenItems(source);

    expect(source, [1, 2, 3, 4, 5]);
  });

  test('counts remaining items after the current page', () {
    expect(remainingKitchenItems(totalItems: 13, currentPage: 0), 9);
    expect(remainingKitchenItems(totalItems: 13, currentPage: 1), 5);
    expect(remainingKitchenItems(totalItems: 13, currentPage: 2), 1);
    expect(remainingKitchenItems(totalItems: 13, currentPage: 3), 0);
  });

  test('throws ArgumentError for invalid pagination arguments', () {
    expect(
      () => paginateKitchenItems([1], perPage: 0),
      throwsArgumentError,
    );
    expect(
      () => remainingKitchenItems(totalItems: 1, currentPage: 0, perPage: 0),
      throwsArgumentError,
    );
    expect(
      () => remainingKitchenItems(totalItems: -1, currentPage: 0),
      throwsArgumentError,
    );
    expect(
      () => remainingKitchenItems(totalItems: 1, currentPage: -1),
      throwsArgumentError,
    );
  });
}

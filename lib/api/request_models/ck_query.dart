import 'ck_filter.dart';
import 'ck_sort_descriptor.dart';

class CKQuery
{
  final String recordType;
  final List<CKFilter>? filterBy;
  final List<CKSortDescriptor>? sortBy;

  CKQuery(this.recordType, {this.filterBy, this.sortBy});

  Map<String, dynamic> toJSON() => {
    'recordType': recordType,
    'filterBy': (filterBy ?? []).map((filter) => filter.toJSON()).toList(),
    'sortBy': (sortBy ?? []).map((sort) => sort.toJSON()).toList()
  };
}
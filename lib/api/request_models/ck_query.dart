import 'ck_filter.dart';

class CKQuery
{
  final String recordType;
  final List<CKFilter>? filterBy;
  // TODO: sortBy

  CKQuery(this.recordType, {this.filterBy});

  Map<String, dynamic> toJSON() => {
    'recordType': recordType,
    'filterBy': (filterBy ?? []).map((filter) => filter.toJSON()).toList(),
  };
}
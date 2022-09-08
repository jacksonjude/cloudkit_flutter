import 'ck_filter.dart';
import 'ck_sort_descriptor.dart';

/// A container class for the record type, filters, and sort descriptors of a CloudKit query.
class CKQuery
{
  final String _recordType;
  final List<CKFilter>? _filterBy;
  final List<CKSortDescriptor>? _sortBy;

  CKQuery(this._recordType, {List<CKFilter>? filterBy, List<CKSortDescriptor>? sortBy}) : _filterBy = filterBy, _sortBy = sortBy;

  /// Convert the query to JSON.
  Map<String, dynamic> toJSON() => {
    'recordType': _recordType,
    'filterBy': (_filterBy ?? []).map((filter) => filter.toJSON()).toList(),
    'sortBy': (_sortBy ?? []).map((sort) => sort.toJSON()).toList()
  };

  static CKQuery fromJSON(Map<String, dynamic> json)
  {
    String recordType = json["recordType"];
    List? filtersJSON = json["filterBy"];
    List? sortByJSON = json["sortBy"];

    return CKQuery(
      recordType,
      filterBy: filtersJSON?.map((json) => CKFilter.fromJSON(json)).toList(),
      sortBy: sortByJSON?.map((json) => CKSortDescriptor.fromJSON(json)).toList()
    );
  }
}
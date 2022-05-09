import 'package:cloudkit_flutter/src/ck_constants.dart';

import '../../parsing/types/ck_field_type.dart';

/// A representation of a CloudKit filter.
class CKFilter {
  final CKComparator _comparator;
  final String _fieldName;
  final Map<String, dynamic> _fieldValueDictionary;
  final double? _distance;

  ///// THIS PART IS A FIX FOR NON-SYSTEMFIELD FILTERS

  dynamic _fieldValue;

  CKFilter(this._fieldName, CKFieldType fieldType, dynamic fieldValue,
      this._comparator,
      {double? distance})
      : _fieldValue = (fieldValue != null)
            ? {'value': fieldValue, 'type': fieldType.record}
            : ((fieldType is num) ? 0 : ""),
        _fieldValueDictionary = {
          'value': {_fieldName: fieldValue},
          'type': fieldType.record
        },
        _distance = distance;

  /// Convert the filter to JSON.
  Map<String, dynamic> toJSON() => {
        'comparator': _comparator._comparatorString,
        (CKConstants.isSystemFieldName(_fieldName)
            ? 'systemFieldName'
            : 'fieldName'): _fieldName,
        'fieldValue': (CKConstants.isSystemFieldName(_fieldName)
            ? _fieldValueDictionary
            : _fieldValue),
        'distance': _distance
      };

  ///// END OF FIX
}



/// A container class for the types of CloudKit comparators used in [CKFilter] objects
class CKComparator
{
  static const EQUALS = CKComparator("EQUALS");
  static const NOT_EQUALS = CKComparator("NOT_EQUALS");
  static const LESS_THAN = CKComparator("LESS_THAN");
  static const LESS_THAN_OR_EQUALS = CKComparator("LESS_THAN_OR_EQUALS");
  static const GREATER_THAN = CKComparator("GREATER_THAN");
  static const GREATER_THAN_OR_EQUALS = CKComparator("GREATER_THAN_OR_EQUALS");
  static const NEAR = CKComparator("NEAR");
  static const CONTAINS_ALL_TOKENS = CKComparator("CONTAINS_ALL_TOKENS");
  static const IN = CKComparator("IN");
  static const NOT_IN = CKComparator("NOT_IN");
  static const CONTAINS_ANY_TOKENS = CKComparator("CONTAINS_ANY_TOKENS");
  static const LIST_CONTAINS = CKComparator("LIST_CONTAINS");
  static const NOT_LIST_CONTAINS = CKComparator("NOT_LIST_CONTAINS");
  static const NOT_LIST_CONTAINS_ANY = CKComparator("NOT_LIST_CONTAINS_ANY");
  static const BEGINS_WITH = CKComparator("BEGINS_WITH");
  static const NOT_BEGINS_WITH = CKComparator("NOT_BEGINS_WITH");
  static const LIST_MEMBER_BEGINS_WITH = CKComparator("LIST_MEMBER_BEGINS_WITH");
  static const NOT_LIST_MEMBER_BEGINS_WITH = CKComparator("NOT_LIST_MEMBER_BEGINS_WITH");
  static const LIST_CONTAINS_ALL = CKComparator("LIST_CONTAINS_ALL");
  static const NOT_LIST_CONTAINS_ALL = CKComparator("NOT_LIST_CONTAINS_ALL");

  final String _comparatorString;

  const CKComparator(this._comparatorString);
}

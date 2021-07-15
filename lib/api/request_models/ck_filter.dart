import '../../parsing/types/ck_field_type.dart';

class CKFilter
{
  final CKComparator comparator;
  final String fieldName;
  final Map<String,dynamic> fieldValueDictionary;
  final double? distance;

  CKFilter(this.comparator, this.fieldName, dynamic fieldValue, CKFieldType fieldType, {this.distance}) : fieldValueDictionary = {'value': {fieldName: fieldValue}, 'type': fieldType.record};

  Map<String, dynamic> toJSON() => {
    'comparator': comparator.comparatorString,
    'systemFieldName': fieldName,
    'fieldValue': fieldValueDictionary,
    'distance': distance
  };
}

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

  final String comparatorString;

  const CKComparator(this.comparatorString);
}
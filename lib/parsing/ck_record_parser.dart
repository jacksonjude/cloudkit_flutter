import 'package:reflectable/reflectable.dart';

import '../ck_constants.dart';
import 'types/ck_reference.dart';
import 'types/ck_asset.dart';
import 'reflector.dart';
import 'annotations/ck_record_type_annotation.dart';
import 'annotations/ck_record_name_annotation.dart';
import 'annotations/ck_field_annotation.dart';
import 'ck_record_structure.dart';
import 'ck_field_structure.dart';
import 'types/ck_field_type.dart';
import '../api/request_models/ck_zone.dart';

/// The class that handles local model class annotation parsing.
class CKRecordParser
{
  static Map<Type,CKRecordStructure> _recordStructures = {};

  /// Create [CKRecordStructure] objects from the provided annotated model classes.
  static void createRecordStructures(List<Type> classTypes)
  {
    Map<Type,CKRecordStructure> recordStructures = {};

    classTypes.forEach((currentType)
    {
      ClassMirror currentClassMirror = reflector.reflectType(currentType) as ClassMirror;

      var ckRecordType = currentType.toString(); // default to local name if none is provided in a CKRecordTypeAnnotation
      if (_isTypeInArray<CKRecordTypeAnnotation>(currentClassMirror.metadata)) // if a CKRecordTypeAnnotation is found above the class declaration ...
      {
        var typeAnnotation = _getTypeFromArray<CKRecordTypeAnnotation>(currentClassMirror.metadata);
        ckRecordType = typeAnnotation.type; // ... set the ckRecordType to the name in the annotation
      }

      var recordStructure = CKRecordStructure(currentType, ckRecordType, currentClassMirror); // create a CKRecordData object to track local and ck field names and types

      currentClassMirror.declarations.values.forEach((field) // iterate through member functions, variables, etc
      {
        if (field is VariableMirror && _isTypeInArray<CKFieldAnnotation>(field.metadata)) // if the field is a variable and tagged with a CKFieldAnnotation ...
        {
          var fieldAnnotation = _getTypeFromArray<CKFieldAnnotation>(field.metadata); // get the annotation object
          recordStructure.fields.add(CKFieldStructure(field.simpleName, fieldAnnotation.name, CKFieldType.fromLocalType(field.reflectedType))); // create a CKFieldData object for the current field
        }
        else if (field is VariableMirror && _isTypeInArray<CKRecordNameAnnotation>(field.metadata)) // if the field is a variable and tagged with a CKRecordNameAnnotation ...
        {
          recordStructure.fields.add(CKFieldStructure(field.simpleName, CKConstants.RECORD_NAME_FIELD, CKFieldType.fromLocalType(field.reflectedType))); // create a CKFieldData object for the recordName field
        }
      });

      recordStructures[currentType] = recordStructure;
    });

    CKRecordParser._recordStructures = recordStructures;
  }

  static bool _isTypeInArray<T>(List<Object> array)
  {
    return array.any((element) => element is T);
  }

  static T _getTypeFromArray<T>(List<Object> array)
  {
    return array.firstWhere((element) => element is T) as T;
  }

  /// Convert a CloudKit record JSON object to a local model object.
  static T recordToLocalObject<T extends Object>(Map<String,dynamic> recordData, {CKDatabase? database})
  {
    recordData = _recordToSimpleJSON(recordData);

    var recordStructure = getRecordStructureFromLocalType(T);

    var newLocalObject = recordStructure.localClassMirror.newInstance("", []);
    var instanceMirror = reflector.reflect(newLocalObject);

    recordStructure.fields.forEach((field) {
      var rawValue = recordData[field.ckName];
      if (rawValue == null) return;

      var convertedValue = convertToLocalValue(field.type, rawValue, database: database);

      instanceMirror.invokeSetter(field.localName, convertedValue);
    });

    return newLocalObject as T;
  }

  /// Convert a single CloudKit record field to a local value.
  static dynamic convertToLocalValue(CKFieldType field, dynamic rawValue, {CKDatabase? database})
  {
    var convertedValue = rawValue;

    switch (field)
    {
      case CKFieldType.STRING_TYPE:
      case CKFieldType.INT_TYPE:
      case CKFieldType.DOUBLE_TYPE:
      // setter below will automatically work for these types; others might also automatically work (other types of lists?)
        convertedValue = rawValue;
        break;

      // brute force required here since List<dynamic> => List<new_type> will fail, but dynamic => new_type works
      case CKFieldType.LIST_STRING_TYPE:
        convertedValue = _castList<String>(rawValue);
        break;
      case CKFieldType.LIST_INT_TYPE:
        convertedValue = _castList<int>(rawValue);
        break;

      case CKFieldType.DATETIME_TYPE:
        convertedValue = DateTime.fromMillisecondsSinceEpoch(rawValue);
        break;

      case CKFieldType.REFERENCE_TYPE:
        convertedValue = CKReference(rawValue[CKConstants.RECORD_NAME_FIELD], database!, zoneID: CKZone(rawValue["zoneID"]["zoneName"]));
        break;
      case CKFieldType.LIST_REFERENCE_TYPE:
        List<CKReference> convertedList = [];
        rawValue.forEach((reference) {
          convertedList.add(CKReference(reference[CKConstants.RECORD_NAME_FIELD], database!, zoneID: CKZone(reference["zoneID"]["zoneName"])));
        });
        convertedValue = convertedList;
        break;

      case CKFieldType.ASSET_TYPE:
        var newAsset = CKAsset(rawValue["size"], downloadURL: rawValue["downloadURL"]);
        convertedValue = newAsset;
        break;

      default:
        if (field.type != null)
        {
          ClassMirror currentClassMirrorForType = reflector.reflectType(field.type!) as ClassMirror;
          var newTestInstance = currentClassMirrorForType.newInstance("", []);
          if (newTestInstance is CKCustomFieldType)
          {
            var baseConvertedValue = convertToLocalValue(CKFieldType.fromRecordType(field.record), rawValue, database: database);
            convertedValue = currentClassMirrorForType.newInstance("fromRecordField", [baseConvertedValue]);
            break;
          }
        }
        throw UnimplementedError("Type (" + field.toString() + ") cannot be converted from JSON to a local type");
    }

    return convertedValue;
  }

  static List<T> _castList<T>(List<dynamic> list)
  {
    List<T> convertedList = [];
    list.forEach((element) {
      convertedList.add(element);
    });
    return convertedList;
  }

  static Future<void> preloadAssets<T extends Object>(T localObject) async
  {
    var instanceMirror = reflector.reflect(localObject);
    var recordStructure = getRecordStructureFromLocalType(T);

    await Future.forEach(recordStructure.fields, (field) async {
      if ((field as CKFieldStructure).type == CKFieldType.ASSET_TYPE)
      {
        var assetObject = instanceMirror.invokeGetter(field.localName) as CKAsset;
        await assetObject.fetchAsset();
      }
    });
  }

  /// Convert a local model object to a CloudKit record JSON object.
  static Map<String,dynamic> localObjectToRecord<T extends Object>(T localObject)
  {
    var recordStructure = getRecordStructureFromLocalType(T);

    var newRecordObject = Map<String,dynamic>();
    var instanceMirror = reflector.reflect(localObject);

    recordStructure.fields.forEach((field)
    {
      var rawValue = instanceMirror.invokeGetter(field.localName);
      if (rawValue == null) return;

      var convertedValue = convertToRecordValue(field.type, rawValue);

      newRecordObject[field.ckName] = convertedValue;
    });

    return _simpleJSONToRecord(recordStructure.ckRecordType, newRecordObject);
  }

  /// Convert a single local value to a CloudKit record field.
  static dynamic convertToRecordValue(CKFieldType field, dynamic rawValue)
  {
    var convertedValue;

    switch (field)
    {
      case CKFieldType.STRING_TYPE:
      case CKFieldType.INT_TYPE:
      case CKFieldType.DOUBLE_TYPE:
      case CKFieldType.LIST_STRING_TYPE:
      case CKFieldType.LIST_INT_TYPE:
      // setter below will automatically work for these types; others might also automatically work (other types of lists?)
        convertedValue = rawValue;
        break;

      case CKFieldType.DATETIME_TYPE:
        convertedValue = (rawValue as DateTime).millisecondsSinceEpoch;
        break;

      case CKFieldType.REFERENCE_TYPE:
        convertedValue = (rawValue as CKReference).toJSON();
        break;
      case CKFieldType.LIST_REFERENCE_TYPE:
        List<Map<String,dynamic>> convertedList = [];
        (rawValue as List).forEach((reference) {
          convertedList.add((reference as CKReference).toJSON());
        });
        convertedValue = convertedList;
        break;

      default:
        if (field.type != null)
        {
          if (rawValue is CKCustomFieldType)
          {
            convertedValue = rawValue.toRecordField();
            break;
          }
        }
        throw UnimplementedError("Type (" + field.toString() + ") cannot be converted from JSON to a local type");
    }

    return convertedValue;
  }

  static CKRecordStructure _getRecordStructure(Type? localType, String? ckRecordType)
  {
    return CKRecordParser._recordStructures.values.firstWhere((recordData) => recordData.localType == localType || recordData.ckRecordType == ckRecordType);
  }

  /// Get a [CKRecordStructure] that matches a given local Type
  static CKRecordStructure getRecordStructureFromLocalType(Type localType)
  {
    return _getRecordStructure(localType, null);
  }

  /// Get a [CKRecordStructure] that matches a given record type string
  static CKRecordStructure getRecordStructureFromRecordType(String ckRecordType)
  {
    return _getRecordStructure(null, ckRecordType);
  }

  static Map<String,dynamic> _recordToSimpleJSON(Map<String,dynamic> recordData)
  {
    var simpleJSONMap = Map<String,dynamic>();

    var fields = recordData["fields"];
    fields.forEach((name, value) {
      simpleJSONMap[name] = value["value"];
    });
    simpleJSONMap[CKConstants.RECORD_NAME_FIELD] = recordData[CKConstants.RECORD_NAME_FIELD];

    return simpleJSONMap;
  }

  static Map<String,dynamic> _simpleJSONToRecord(String recordType, Map<String,dynamic> simpleJSONMap)
  {
    var recordStructure = getRecordStructureFromRecordType(recordType);
    var recordData = Map<String,dynamic>();

    recordData[CKConstants.RECORD_NAME_FIELD] = simpleJSONMap[CKConstants.RECORD_NAME_FIELD];
    recordData[CKConstants.RECORD_TYPE_FIELD] = recordType;

    var fields = Map<String,dynamic>();

    simpleJSONMap.forEach((name, value) {
      if (name == CKConstants.RECORD_NAME_FIELD) return;

      var recordField = recordStructure.fields.firstWhere((field) => field.ckName == name);
      fields[name] = {
        "value": value,
        "type": recordField.type.record
      };
    });

    recordData[CKConstants.RECORD_FIELDS_FIELD] = fields;

    return recordData;
  }
}
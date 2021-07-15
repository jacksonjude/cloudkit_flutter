import 'package:reflectable/reflectable.dart';

class Reflector extends Reflectable
{
  const Reflector() : super(
    invokingCapability,
    typingCapability,
    reflectedTypeCapability,
  );
}

const reflector = const Reflector();
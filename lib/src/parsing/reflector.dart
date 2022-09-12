import '/reflectable.dart';

/// Custom [Reflectable] subclass with invokingCapability, typingCapability, and reflectedTypeCapability.
class Reflector extends Reflectable
{
  const Reflector() : super(
    invokingCapability,
    typingCapability,
    reflectedTypeCapability,
  );
}

/// Singleton instance of the custom [Reflector] class.
const reflector = const Reflector();
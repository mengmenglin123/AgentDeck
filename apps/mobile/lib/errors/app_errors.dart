/// Typed errors for Host connectivity (mirror Python protocol package).
class AuthError implements Exception {
  AuthError(this.message);
  final String message;
  @override
  String toString() => 'AuthError: $message';
}

class DisconnectedError implements Exception {
  DisconnectedError(this.message);
  final String message;
  @override
  String toString() => 'DisconnectedError: $message';
}

class ProtocolError implements Exception {
  ProtocolError(this.message);
  final String message;
  @override
  String toString() => 'ProtocolError: $message';
}

class PermissionRequired implements Exception {
  PermissionRequired(this.message, {this.requestId});
  final String message;
  final String? requestId;
  @override
  String toString() => 'PermissionRequired: $message';
}

class AgentFailed implements Exception {
  AgentFailed(this.message);
  final String message;
  @override
  String toString() => 'AgentFailed: $message';
}

class CapabilitySet {
  CapabilitySet._(Set<String> values)
      : values = Set<String>.unmodifiable(values);

  factory CapabilitySet.from(dynamic raw) {
    final values = <String>{};
    if (raw is Iterable) {
      for (final item in raw) {
        final value = item?.toString().trim() ?? '';
        if (value.isNotEmpty) values.add(value);
      }
    }
    return CapabilitySet._(values);
  }

  final Set<String> values;

  bool get isEmpty => values.isEmpty;
  bool supports(String capability) => values.contains(capability);
  List<String> toList() => values.toList(growable: false);
}

class HostRuntimeInfo {
  HostRuntimeInfo({
    required this.version,
    required this.adapterType,
    required this.hermesProcess,
    required this.capabilities,
  });

  factory HostRuntimeInfo.fromStatus(Map<String, dynamic>? status) {
    final data = status ?? const <String, dynamic>{};
    final hermes = data['hermes'];
    final hermesMap = hermes is Map ? hermes : const <String, dynamic>{};
    final directAdapter = data['adapter']?.toString().trim() ?? '';
    final nestedAdapter = hermesMap['adapter']?.toString().trim() ?? '';
    return HostRuntimeInfo(
      version: data['version']?.toString() ?? '',
      adapterType: directAdapter.isNotEmpty
          ? directAdapter
          : nestedAdapter.isNotEmpty
              ? nestedAdapter
              : 'unknown',
      hermesProcess: hermesMap['process'] == true,
      capabilities: CapabilitySet.from(data['capabilities']),
    );
  }

  final String version;
  final String adapterType;
  final bool hermesProcess;
  final CapabilitySet capabilities;

  bool get isRealHermes => hermesProcess || adapterType == 'hermes';

  String get displayLabel {
    if (isRealHermes) return '真 Hermes';
    if (adapterType == 'mock') return 'Mock';
    if (adapterType == 'unknown') return '兼容 Host';
    return adapterType;
  }
}

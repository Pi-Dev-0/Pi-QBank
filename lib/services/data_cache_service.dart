class DataCacheService {
  static final DataCacheService _instance = DataCacheService._internal();
  factory DataCacheService() => _instance;
  DataCacheService._internal();

  final Map<String, List<Map<String, dynamic>>> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheDuration = Duration(hours: 1);

  Future<List<Map<String, dynamic>>> fetchData(
    String url,
    String key,
    Future<List<Map<String, dynamic>>> Function() fetchFunction,
  ) async {
    if (_cache.containsKey(key)) {
      final timestamp = _cacheTimestamps[key];
      final now = DateTime.now();
      if (timestamp != null && 
          now.difference(timestamp) < _cacheDuration) {
        return _cache[key]!;
      } else {
        _cache.remove(key);
        _cacheTimestamps.remove(key);
      }
    }

    final data = await fetchFunction();
    _cache[key] = data;
    _cacheTimestamps[key] = DateTime.now();
    return data;
  }

  void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }

  bool hasCachedData(String key) {
    return _cache.containsKey(key) && 
           DateTime.now().difference(_cacheTimestamps[key]!) < _cacheDuration;
  }
} 
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Modern Maps',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7BFF),
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.goldmanTextTheme(),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MapPage(),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with TickerProviderStateMixin {
  MapController? _mapController;

  // Animation Controllers
  late AnimationController _loadingController;
  late AnimationController _locationCardController;
  late AnimationController _sidebarController;
  late AnimationController _mapTransitionController;
  late AnimationController _statsTransitionController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _sidebarSlideAnimation;
  late Animation<double> _mapFadeAnimation;
  late Animation<double> _statsSlideAnimation;
  late Animation<double> _statsOpacityAnimation;

  // Timers
  Timer? _locationTimer;
  Timer? _dataUpdateTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Core State
  bool isOnline = true;
  bool forceOffline = false;
  bool _isInitializing = true;
  bool _mapReady = false;
  bool isGettingRoute = false;
  bool isNavigating = false;
  bool showLocationCard = false;
  bool _isTransitioning = false;

  // Vehicle Data - Enhanced
  int batteryLevel = 85;
  int speed = 0;
  int motorTemp = 45;
  int signalStrength = 4;
  String gpsAccuracy = 'İyi';
  String trafficInfo = 'Hafif Trafik';

  // Navigation Data
  double routeDistance = 0; // km
  int routeDuration = 0; // dakika
  String arrivalTime = '';

  // Map Data
  Position? currentPosition;
  LatLng? selectedLocation;
  LocationInfo? selectedLocationInfo;
  List<LatLng> routePoints = [];
  String routeInfo = '';

  // Map Layers
  String currentMapStyle = 'standard';
  final List<MapLayer> availableLayers = [
    MapLayer('standard', 'Standart', Icons.map),
    MapLayer('satellite', 'Uydu', Icons.satellite_alt),
    MapLayer('terrain', 'Arazi', Icons.terrain),
  ];

  // Arama state
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<SearchResult> _searchResults = [];
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebouncer;

  // Sayfalama state
  int _currentStatsPage = 0;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startEnhancedDataUpdate();
    _initializeApp();
  }

  void _initializeAnimations() {
    _loadingController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _locationCardController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _sidebarController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _mapTransitionController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _statsTransitionController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _pulseAnimation = CurvedAnimation(
      parent: _loadingController,
      curve: Curves.easeInOut,
    );

    _sidebarSlideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _sidebarController,
      curve: Curves.easeOutCubic,
    ));

    _mapFadeAnimation = CurvedAnimation(
      parent: _mapTransitionController,
      curve: Curves.easeInOut,
    );

    _statsSlideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _statsTransitionController,
      curve: Curves.easeOutBack,
    ));

    _statsOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _statsTransitionController,
      curve: Curves.easeInOut,
    ));

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _sidebarController.forward();
        _statsTransitionController.forward();
      }
    });
  }

  void _startEnhancedDataUpdate() {
    _dataUpdateTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final random = math.Random();
      setState(() {
        if (isNavigating) {
          speed = 25 + random.nextInt(35);
          batteryLevel = math.max(10, batteryLevel - random.nextInt(2));
          motorTemp = 45 + random.nextInt(15);
        } else {
          speed = random.nextInt(3);
          motorTemp = 40 + random.nextInt(10);
        }
        signalStrength = math.max(2, 5 - random.nextInt(2));
        gpsAccuracy = signalStrength >= 4
            ? 'Mükemmel'
            : signalStrength >= 3
                ? 'İyi'
                : 'Orta';
      });
    });
  }

  Future<void> _initializeApp() async {
    try {
      debugPrint('🚀 Başlatılıyor...');

      await _checkConnectivity();
      _mapController = MapController();

      if (mounted) {
        setState(() => _isInitializing = false);
        _requestLocationAsync();
      }

      debugPrint('✅ Başlatma tamamlandı');
    } catch (e) {
      debugPrint('❌ Başlatma hatası: $e');
      if (mounted) {
        setState(() => _isInitializing = false);
        _setDefaultLocation();
      }
    }
  }

  Future<void> _checkConnectivity() async {
    try {
      final results = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 3));

      if (mounted) {
        setState(() {
          isOnline = !results.contains(ConnectivityResult.none);
        });
      }

      _connectivitySubscription =
          Connectivity().onConnectivityChanged.listen((results) {
        if (mounted) {
          final newOnlineStatus = !results.contains(ConnectivityResult.none);
          if (newOnlineStatus != isOnline) {
            setState(() {
              isOnline = newOnlineStatus;
            });
            _animateMapTransition();
          }
        }
      });
    } catch (e) {
      debugPrint('⚠️ Bağlantı kontrolü hatası: $e');
      if (mounted) {
        setState(() => isOnline = false);
      }
    }
  }

  void _animateMapTransition() {
    if (!mounted) return;

    setState(() => _isTransitioning = true);
    _mapTransitionController.reset();
    _mapTransitionController.forward().then((_) {
      if (mounted) {
        setState(() => _isTransitioning = false);
      }
    });
  }

  void _requestLocationAsync() {
    _locationTimer = Timer(const Duration(milliseconds: 500), () async {
      await _handleLocationPermissions();
    });
  }

  Future<void> _handleLocationPermissions() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint('❌ Konum servisleri kapalı');
        _setDefaultLocation();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('📍 Konum izni durumu: $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 10));
        debugPrint('📍 İzin talebi sonucu: $permission');
      }

      if (permission == LocationPermission.deniedForever) {
        _setDefaultLocation();
        return;
      }

      if (permission == LocationPermission.denied) {
        _setDefaultLocation();
        return;
      }

      await _getCurrentLocation();
    } catch (e) {
      debugPrint('❌ İzin alma hatası: $e');
      _setDefaultLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;

    try {
      debugPrint('📍 Konum alınıyor...');

      try {
        final lastPosition = await Geolocator.getLastKnownPosition()
            .timeout(const Duration(seconds: 3));

        if (lastPosition != null && mounted) {
          debugPrint(
              '✅ Son konum: ${lastPosition.latitude}, ${lastPosition.longitude}');
          setState(() => currentPosition = lastPosition);
          _moveMapToLocation(lastPosition);
          _getCurrentPositionInBackground();
          return;
        }
      } catch (e) {
        debugPrint('⚠️ Son konum alma hatası: $e');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      ).timeout(const Duration(seconds: 15));

      if (mounted) {
        debugPrint(
            '✅ Güncel konum: ${position.latitude}, ${position.longitude}');
        setState(() => currentPosition = position);
        _moveMapToLocation(position);
      }
    } catch (e) {
      debugPrint('⚠️ Konum alma hatası: $e');
      _setDefaultLocation();
    }
  }

  void _getCurrentPositionInBackground() {
    Timer(const Duration(seconds: 5), () async {
      if (!mounted) return;

      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 8),
        );

        if (mounted) {
          setState(() => currentPosition = position);
          debugPrint('✅ Güncel konum güncellendi');
        }
      } catch (e) {
        debugPrint('⚠️ Background konum güncellemesi hatası: $e');
      }
    });
  }

  void _moveMapToLocation(Position position) {
    if (!_mapReady || _mapController == null || !mounted) {
      debugPrint('⏳ Harita henüz hazır değil');
      return;
    }

    try {
      _mapController!.move(
        LatLng(position.latitude, position.longitude),
        15,
      );
    } catch (e) {
      debugPrint('❌ Harita hareket hatası: $e');
    }
  }

  void _setDefaultLocation() {
    const defaultLat = 41.0082;
    const defaultLng = 28.9784;

    final defaultPosition = Position(
      latitude: defaultLat,
      longitude: defaultLng,
      timestamp: DateTime.now(),
      accuracy: 100,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      headingAccuracy: 0,
    );

    if (mounted) {
      setState(() => currentPosition = defaultPosition);

      if (_mapReady && _mapController != null) {
        Timer(const Duration(milliseconds: 300), () {
          if (mounted) {
            try {
              _mapController!.move(const LatLng(defaultLat, defaultLng), 13);
            } catch (e) {
              debugPrint('❌ Varsayılan konum hatası: $e');
            }
          }
        });
      }
    }
  }

  void _onMapReady() {
    debugPrint('🗺️ Harita hazır');
    if (mounted) {
      setState(() => _mapReady = true);

      if (currentPosition != null) {
        Timer(const Duration(milliseconds: 500), () {
          if (mounted && currentPosition != null) {
            _moveMapToLocation(currentPosition!);
          }
        });
      }
    }
  }

  Future<void> _onMapTap(LatLng point) async {
    if (!mounted) return;

    setState(() {
      selectedLocation = point;
      showLocationCard = true;
      selectedLocationInfo = null;
    });

    _locationCardController.forward();

    final isOfflineMode = forceOffline || !isOnline;
    if (isOfflineMode) {
      _getOfflineLocationInfo(point);
    } else {
      await _getOnlineLocationInfo(point);
    }
  }

  Future<void> _getOnlineLocationInfo(LatLng point) async {
    try {
      final url = 'https://nominatim.openstreetmap.org/reverse?'
          'format=json&lat=${point.latitude}&lon=${point.longitude}&zoom=18&addressdetails=1';

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'ModernMapsApp/1.0'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);

        String name = 'Bilinmeyen Konum';
        String address = '';
        String category = '';

        if (data['display_name'] != null) {
          final displayName = data['display_name'] as String;
          final parts = displayName.split(', ');

          if (parts.isNotEmpty) {
            name = parts[0];
            if (parts.length > 1) {
              address = parts.skip(1).take(3).join(', ');
            }
          }
        }

        if (data['category'] != null) {
          category = _translateCategory(data['category']);
        }

        if (mounted) {
          setState(() {
            selectedLocationInfo = LocationInfo(
              name: name,
              address: address,
              category: category,
              coordinates:
                  '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
              isOnline: true,
            );
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Konum bilgisi alma hatası: $e');
      _getOfflineLocationInfo(point);
    }
  }

  void _getOfflineLocationInfo(LatLng point) {
    if (!mounted) return;

    final random =
        math.Random(point.latitude.hashCode + point.longitude.hashCode);
    const locations = ['Konum', 'Nokta', 'Alan', 'Bölge', 'Mevki'];
    const adjectives = ['Seçilen', 'İşaretli', 'Belirlenen', 'Hedef'];

    final locationName =
        '${adjectives[random.nextInt(adjectives.length)]} ${locations[random.nextInt(locations.length)]}';

    setState(() {
      selectedLocationInfo = LocationInfo(
        name: locationName,
        address: 'Çevrimdışı mod',
        category: 'Koordinat',
        coordinates:
            '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
        isOnline: false,
      );
    });
  }

  String _translateCategory(String category) {
    const categoryMap = {
      'amenity': 'Tesis',
      'shop': 'Mağaza',
      'building': 'Bina',
      'highway': 'Yol',
      'natural': 'Doğal Alan',
      'leisure': 'Eğlence',
      'tourism': 'Turizm',
      'place': 'Yer',
      'landuse': 'Arazi',
    };
    return categoryMap[category] ?? 'Konum';
  }

  void _clearSelection() {
    if (!mounted) return;

    setState(() {
      selectedLocation = null;
      selectedLocationInfo = null;
      showLocationCard = false;
    });
    _locationCardController.reverse();
  }

  void _hideLocationCard() {
    _locationCardController.reverse();
    Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          showLocationCard = false;
          selectedLocation = null;
          selectedLocationInfo = null;
        });
      }
    });
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes dk';
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) {
      return '$hours saat';
    }
    return '$hours saat $mins dk';
  }

  String _calculateArrivalTime(int minutes) {
    final now = DateTime.now();
    final arrival = now.add(Duration(minutes: minutes));
    return '${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _calculateRoute() async {
    if (currentPosition == null || selectedLocation == null) return;

    final isOfflineMode = forceOffline || !isOnline;
    if (isOfflineMode) {
      return;
    }

    setState(() => isGettingRoute = true);

    try {
      final start =
          LatLng(currentPosition!.latitude, currentPosition!.longitude);
      final end = selectedLocation!;

      final route = await _getOnlineRoute(start, end);
      final info = await _getRouteInfo(start, end, true);

      if (mounted) {
        setState(() {
          routePoints = route;
          routeInfo = info;
          isNavigating = true;
          showLocationCard = false;
          speed = 30;
        });

        _hideLocationCard();
        _fitMapToRoute();
      }
    } catch (e) {
      debugPrint('❌ Rota hatası: $e');
    } finally {
      if (mounted) {
        setState(() => isGettingRoute = false);
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty || !mounted) return;

    setState(() {
      _isSearching = true;
      _searchResults.clear();
    });

    try {
      final encodedQuery = Uri.encodeComponent(query.trim());
      final url = 'https://nominatim.openstreetmap.org/search?'
          'format=json&q=$encodedQuery&limit=8&addressdetails=1&dedupe=1&'
          'bounded=0&countrycodes=tr';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'ModernMapsApp/1.0',
          'Accept': 'application/json',
          'Accept-Language': 'tr,en',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && mounted) {
        final List<dynamic> data = json.decode(response.body);

        final results = <SearchResult>[];
        final seen = <String>{};

        for (final item in data) {
          if (item['lat'] != null &&
              item['lon'] != null &&
              item['display_name'] != null) {
            final displayName = item['display_name'] as String;

            if (seen.contains(displayName)) continue;
            seen.add(displayName);

            String name = displayName;
            String shortName = '';

            final parts = displayName.split(', ');
            if (parts.isNotEmpty) {
              shortName = parts[0];
              if (parts.length > 1) {
                final location = parts.skip(1).take(2).join(', ');
                name = '$shortName, $location';
              }
            }

            results.add(SearchResult(
              name: name,
              shortName: shortName,
              latitude: double.tryParse(item['lat']) ?? 0,
              longitude: double.tryParse(item['lon']) ?? 0,
              type: _translateCategory(item['type'] ?? item['class'] ?? ''),
              importance:
                  double.tryParse(item['importance']?.toString() ?? '0') ?? 0,
            ));
          }
        }

        results.sort((a, b) => b.importance.compareTo(a.importance));

        if (mounted) {
          setState(() {
            _searchResults = results.take(6).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Arama hatası: $e');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _onSearchChanged(String value) {
    _searchDebouncer?.cancel();

    if (value.trim().isEmpty) {
      setState(() {
        _searchResults.clear();
      });
      return;
    }

    if (value.trim().length < 2) return;

    _searchDebouncer = Timer(const Duration(milliseconds: 800), () {
      _searchLocation(value);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _searchResults.clear();
    });
  }

  void _goToSearchResult(SearchResult result) {
    if (!mounted) return;

    final location = LatLng(result.latitude, result.longitude);

    _mapController?.move(location, 15);

    setState(() {
      selectedLocation = location;
      selectedLocationInfo = LocationInfo(
        name: result.shortName.isNotEmpty ? result.shortName : result.name,
        address: result.name,
        category: result.type,
        coordinates:
            '${result.latitude.toStringAsFixed(4)}, ${result.longitude.toStringAsFixed(4)}',
        isOnline: true,
      );
      showLocationCard = true;
      _searchResults.clear();
      _searchController.clear();
    });

    _locationCardController.forward();
  }

  Widget _buildSosisStatCard(
      String title, String value, Color color, IconData icon) {
    return Container(
      width: 130,
      height: 70,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(35),
        border: Border.all(
          color: color,
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 12,
            offset: const Offset(-3, 3),
          ),
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: color,
            size: 26,
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.goldman(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                title,
                style: GoogleFonts.goldman(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<List<LatLng>> _getOnlineRoute(LatLng start, LatLng end) async {
    final url = 'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=polyline';

    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['routes']?.isNotEmpty == true) {
        final route = data['routes'][0];

        // Distance ve duration'ı kaydet
        if (route['distance'] != null && route['duration'] != null) {
          routeDistance = (route['distance'] / 1000); // metre -> km
          routeDuration = (route['duration'] / 60).round(); // saniye -> dakika
          arrivalTime = _calculateArrivalTime(routeDuration);
        }

        return _decodePolyline(route['geometry']);
      }
    }

    throw Exception('Rota bulunamadı');
  }

  Future<String> _getRouteInfo(LatLng start, LatLng end, bool online) async {
    if (online && routeDuration > 0 && routeDistance > 0) {
      return '${routeDistance.toStringAsFixed(1)} km • ${_formatDuration(routeDuration)} • ${arrivalTime}\'de varış';
    }

    final distance = Geolocator.distanceBetween(
          start.latitude,
          start.longitude,
          end.latitude,
          end.longitude,
        ) /
        1000;

    final time = (distance / 35 * 60).round();
    final arrival = _calculateArrivalTime(time);

    return '${distance.toStringAsFixed(1)} km • ${_formatDuration(time)} • ${arrival}\'de varış';
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0;
    final len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int shift = 0, result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      final dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      final dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  void _fitMapToRoute() {
    if (!_mapReady ||
        routePoints.isEmpty ||
        _mapController == null ||
        !mounted) {
      return;
    }

    try {
      final bounds = LatLngBounds.fromPoints(routePoints);

      _mapController!.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50),
        ),
      );
    } catch (e) {
      debugPrint('❌ Route fit hatası: $e');
    }
  }

  void _clearRoute() {
    if (!mounted) return;

    setState(() {
      routePoints.clear();
      routeInfo = '';
      isNavigating = false;
      selectedLocation = null;
      selectedLocationInfo = null;
      showLocationCard = false;
      speed = 0;
      routeDistance = 0;
      routeDuration = 0;
      arrivalTime = '';
    });
  }

  void _toggleOfflineMode() {
    if (!mounted) return;

    setState(() => forceOffline = !forceOffline);
    _animateMapTransition();

    if (selectedLocation != null) {
      _clearSelection();
    }
  }

  Widget _buildAnimatedStatsPanel() {
    final isOfflineMode = forceOffline || !isOnline;

    final List<Map<String, dynamic>> allStats = [
      {
        'title': 'KM/H',
        'value': '$speed',
        'color': isNavigating ? Colors.green : Colors.grey[400]!,
        'icon': Icons.speed,
      },
      {
        'title': 'PİL',
        'value': '$batteryLevel%',
        'color': _getBatteryColor(),
        'icon': Icons.battery_std,
      },
      {
        'title': 'SICAK',
        'value': '${motorTemp}°',
        'color': _getTemperatureColor(),
        'icon': Icons.device_thermostat,
      },
      {
        'title': 'SİNYAL',
        'value': '$signalStrength',
        'color': _getSignalColor(),
        'icon': Icons.signal_cellular_alt,
      },
      {
        'title': 'GPS',
        'value': _getGpsShortStatus(),
        'color': _getGpsColor(),
        'icon': Icons.gps_fixed,
      },
      {
        'title': 'MOD',
        'value': isOfflineMode ? 'OFF' : 'ON',
        'color': isOfflineMode ? Colors.deepOrange : Colors.cyan,
        'icon': isOfflineMode ? Icons.offline_bolt : Icons.wifi,
      },
    ];

    final startIndex = _currentStatsPage * 3;
    final currentStats = allStats.skip(startIndex).take(3).toList();

    return AnimatedBuilder(
      animation: _statsTransitionController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset((1 - _statsSlideAnimation.value) * 100, 0),
          child: Opacity(
            opacity: _statsOpacityAnimation.value,
            child: Column(
              children: [
                for (int i = 0; i < currentStats.length; i++) ...[
                  Transform.translate(
                    offset:
                        Offset(0, (1 - _statsSlideAnimation.value) * (i * 20)),
                    child: _buildSosisStatCard(
                      currentStats[i]['title'],
                      currentStats[i]['value'],
                      currentStats[i]['color'],
                      currentStats[i]['icon'],
                    ),
                  ),
                  if (i < currentStats.length - 1) const SizedBox(height: 15),
                ],
                const SizedBox(height: 25),
                GestureDetector(
                  onTap: () {
                    _statsTransitionController.reset();
                    setState(() {
                      _currentStatsPage = _currentStatsPage == 0 ? 1 : 0;
                    });
                    _statsTransitionController.forward();
                  },
                  child: Transform.scale(
                    scale: _statsSlideAnimation.value,
                    child: Container(
                      width: 65,
                      height: 65,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.85),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.7),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.6),
                            blurRadius: 15,
                            offset: const Offset(-2, 3),
                          ),
                          BoxShadow(
                            color: Colors.white.withOpacity(0.1),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(
                        _currentStatsPage == 0
                            ? Icons.keyboard_double_arrow_down
                            : Icons.keyboard_double_arrow_up,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Transform.scale(
                  scale: _statsSlideAnimation.value,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < 2; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentStatsPage == i ? 12 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: _currentStatsPage == i
                                ? Colors.white
                                : Colors.white.withOpacity(0.4),
                            boxShadow: [
                              if (_currentStatsPage == i)
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.6),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getGpsShortStatus() {
    if (gpsAccuracy == 'Mükemmel') return 'A+';
    if (gpsAccuracy == 'İyi') return 'B';
    return 'C';
  }

  Color _getBatteryColor() {
    if (batteryLevel > 60) return Colors.green;
    if (batteryLevel > 30) return Colors.orange;
    return Colors.red;
  }

  Color _getSignalColor() {
    if (signalStrength >= 4) return Colors.green;
    if (signalStrength >= 3) return Colors.orange;
    return Colors.red;
  }

  Color _getGpsColor() {
    if (gpsAccuracy == 'Mükemmel') return Colors.green;
    if (gpsAccuracy == 'İyi') return Colors.orange;
    return Colors.red;
  }

  Color _getTemperatureColor() {
    if (motorTemp > 55) return Colors.red;
    if (motorTemp > 45) return Colors.orange;
    return Colors.green;
  }

  void _showMapStylePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    Icons.layers,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Harita Stili Seç',
                    style: GoogleFonts.goldman(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...availableLayers.map((layer) => ListTile(
                          leading: Icon(layer.icon, color: Colors.grey[600]),
                          title: Text(
                            layer.name,
                            style: GoogleFonts.goldman(),
                          ),
                          trailing: currentMapStyle == layer.id
                              ? const Icon(Icons.check_circle,
                                  color: Color(0xFF2E7BFF))
                              : null,
                          onTap: () {
                            setState(() => currentMapStyle = layer.id);
                            _animateMapTransition();
                            Navigator.pop(context);
                          },
                        )),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getMapTileUrl(bool isOfflineMode) {
    switch (currentMapStyle) {
      case 'satellite':
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case 'terrain':
        return 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
      default:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }

  @override
  void dispose() {
    _loadingController.dispose();
    _locationCardController.dispose();
    _sidebarController.dispose();
    _mapTransitionController.dispose();
    _statsTransitionController.dispose();
    _connectivitySubscription?.cancel();
    _locationTimer?.cancel();
    _dataUpdateTimer?.cancel();
    _searchDebouncer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2E7BFF)),
              ),
              const SizedBox(height: 16),
              Text(
                'Harita Yükleniyor...',
                style: GoogleFonts.goldman(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isOfflineMode = forceOffline || !isOnline;

    return Scaffold(
      backgroundColor: Colors.grey[300],
      body: Stack(
        children: [
          // Main Map
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _mapFadeAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: _isTransitioning ? _mapFadeAnimation.value : 1.0,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: const LatLng(41.0082, 28.9784),
                      initialZoom: 13,
                      minZoom: 3,
                      maxZoom: 18,
                      onTap: (_, point) => _onMapTap(point),
                      onMapReady: _onMapReady,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: _getMapTileUrl(isOfflineMode),
                        maxZoom: 18,
                        userAgentPackageName: 'com.modernmaps.app',
                        errorTileCallback: (tile, error, stackTrace) {},
                      ),
                      if (routePoints.isNotEmpty && !isOfflineMode)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: routePoints,
                              strokeWidth: 4,
                              color: const Color(0xFF2E7BFF),
                              borderStrokeWidth: 2,
                              borderColor: Colors.white,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (currentPosition != null)
                            Marker(
                              point: LatLng(
                                currentPosition!.latitude,
                                currentPosition!.longitude,
                              ),
                              width: 50,
                              height: 50,
                              child: AnimatedBuilder(
                                animation: _pulseAnimation,
                                builder: (context, child) {
                                  return Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: 50 *
                                            (1 + _pulseAnimation.value * 0.3),
                                        height: 50 *
                                            (1 + _pulseAnimation.value * 0.3),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: (isOfflineMode
                                                  ? Colors.orange
                                                  : Colors.blue)
                                              .withOpacity(0.3 *
                                                  (1 - _pulseAnimation.value)),
                                        ),
                                      ),
                                      Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color: isOfflineMode
                                              ? Colors.orange
                                              : Colors.blue,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white, width: 2),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          isOfflineMode
                                              ? Icons.offline_pin
                                              : Icons.navigation,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          if (selectedLocation != null)
                            Marker(
                              point: selectedLocation!,
                              width: 40,
                              height: 40,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isOfflineMode
                                      ? Colors.deepOrange
                                      : Colors.red,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  isOfflineMode
                                      ? Icons.location_pin
                                      : Icons.place,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Top Bar - Search veya Route Info
          if (!isOfflineMode)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 150,
              child: routeInfo.isNotEmpty
                  ? Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7BFF).withOpacity(0.95),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.navigation,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              routeInfo,
                              style: GoogleFonts.goldman(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _clearRoute,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.grey[50]!,
                                  Colors.white,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              decoration: InputDecoration(
                                hintText: 'Konum ara...',
                                hintStyle: GoogleFonts.goldman(
                                  color: Colors.grey[500],
                                  fontSize: 16,
                                ),
                                prefixIcon: _isSearching
                                    ? const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Color(0xFF2E7BFF)),
                                          ),
                                        ),
                                      )
                                    : Icon(Icons.search,
                                        color: Colors.grey[600], size: 24),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.clear,
                                            color: Colors.grey[600]),
                                        onPressed: _clearSearch,
                                        splashRadius: 20,
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.transparent,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                              ),
                              style: GoogleFonts.goldman(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              onSubmitted: _searchLocation,
                              onChanged: _onSearchChanged,
                            ),
                          ),
                          if (_searchResults.isNotEmpty)
                            Container(
                              constraints: const BoxConstraints(maxHeight: 250),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(20),
                                  bottomRight: Radius.circular(20),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(20),
                                  bottomRight: Radius.circular(20),
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: _searchResults.length,
                                  separatorBuilder: (context, index) => Divider(
                                    height: 1,
                                    color: Colors.grey[200],
                                    indent: 16,
                                    endIndent: 16,
                                  ),
                                  itemBuilder: (context, index) {
                                    final result = _searchResults[index];
                                    return ListTile(
                                      dense: true,
                                      leading: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2E7BFF)
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.place,
                                          color: Color(0xFF2E7BFF),
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        result.shortName.isNotEmpty
                                            ? result.shortName
                                            : result.name,
                                        style: GoogleFonts.goldman(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (result.type.isNotEmpty)
                                            Text(
                                              result.type,
                                              style: GoogleFonts.goldman(
                                                color: Colors.grey[600],
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          if (result.shortName.isNotEmpty)
                                            Text(
                                              result.name,
                                              style: GoogleFonts.goldman(
                                                color: Colors.grey[500],
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                      trailing: Icon(
                                        Icons.arrow_forward_ios,
                                        color: Colors.grey[400],
                                        size: 16,
                                      ),
                                      onTap: () => _goToSearchResult(result),
                                    );
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),

          // Sağ Stats Panel
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + 80,
            child: SlideTransition(
              position: _sidebarSlideAnimation,
              child: _buildAnimatedStatsPanel(),
            ),
          ),

          // Sol Alt Kontroller
          Positioned(
            left: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  onPressed: _toggleOfflineMode,
                  backgroundColor:
                      isOfflineMode ? Colors.deepOrange : Colors.cyan,
                  elevation: 8,
                  child: Icon(
                    isOfflineMode ? Icons.offline_bolt : Icons.wifi,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  onPressed: _getCurrentLocation,
                  backgroundColor: isOfflineMode
                      ? Colors.deepOrange
                      : const Color(0xFF2E7BFF),
                  elevation: 8,
                  child: Icon(
                    isOfflineMode
                        ? Icons.my_location_outlined
                        : Icons.my_location,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  onPressed: _showMapStylePicker,
                  backgroundColor: Colors.green,
                  mini: true,
                  elevation: 6,
                  child: const Icon(Icons.layers, color: Colors.white),
                ),
              ],
            ),
          ),

          // Location Card
          if (showLocationCard)
            AnimatedBuilder(
              animation: _locationCardController,
              builder: (context, child) {
                return Positioned(
                  left: 16,
                  right: 150,
                  bottom: 16,
                  child: Transform.translate(
                    offset:
                        Offset(0, (1 - _locationCardController.value) * 250),
                    child: Opacity(
                      opacity: _locationCardController.value,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isOfflineMode
                                          ? Colors.deepOrange.withOpacity(0.1)
                                          : Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      isOfflineMode
                                          ? Icons.location_pin
                                          : Icons.place,
                                      color: isOfflineMode
                                          ? Colors.deepOrange
                                          : Colors.blue,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          selectedLocationInfo?.name ??
                                              'Konum Yükleniyor...',
                                          style: GoogleFonts.goldman(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (selectedLocationInfo
                                                ?.category.isNotEmpty ==
                                            true)
                                          Text(
                                            selectedLocationInfo!.category,
                                            style: GoogleFonts.goldman(
                                              fontSize: 12,
                                              color: isOfflineMode
                                                  ? Colors.deepOrange
                                                  : Colors.blue,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _hideLocationCard,
                                    icon: const Icon(Icons.close),
                                    iconSize: 20,
                                  ),
                                ],
                              ),
                              if (selectedLocationInfo != null) ...[
                                const SizedBox(height: 12),
                                if (selectedLocationInfo!.address.isNotEmpty)
                                  Text(
                                    selectedLocationInfo!.address,
                                    style: GoogleFonts.goldman(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Text(
                                  selectedLocationInfo!.coordinates,
                                  style: GoogleFonts.goldman(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                if (!isOfflineMode)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: isGettingRoute
                                              ? null
                                              : _calculateRoute,
                                          icon: isGettingRoute
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                                Color>(
                                                            Colors.white),
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.navigation,
                                                  size: 16,
                                                ),
                                          label: Text(
                                            isGettingRoute
                                                ? 'Hesaplanıyor...'
                                                : 'Rota Hesapla',
                                            style: GoogleFonts.goldman(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF2E7BFF),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 14),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            elevation: 4,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      OutlinedButton(
                                        onPressed: _clearSelection,
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.all(14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFF2E7BFF),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.clear,
                                          color: Color(0xFF2E7BFF),
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.orange.withOpacity(0.3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.offline_pin,
                                          color: Colors.orange,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Offline Mod',
                                                style: GoogleFonts.goldman(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.orange[700],
                                                ),
                                              ),
                                              Text(
                                                'Sadece koordinat bilgisi mevcut',
                                                style: GoogleFonts.goldman(
                                                  fontSize: 12,
                                                  color: Colors.orange[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: _clearSelection,
                                          icon: Icon(
                                            Icons.close,
                                            color: Colors.orange[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// Model Sınıfları
class MapLayer {
  final String id;
  final String name;
  final IconData icon;

  MapLayer(this.id, this.name, this.icon);
}

class LocationInfo {
  final String name;
  final String address;
  final String category;
  final String coordinates;
  final bool isOnline;

  LocationInfo({
    required this.name,
    required this.address,
    required this.category,
    required this.coordinates,
    required this.isOnline,
  });
}

class SearchResult {
  final String name;
  final String shortName;
  final double latitude;
  final double longitude;
  final String type;
  final double importance;

  SearchResult({
    required this.name,
    this.shortName = '',
    required this.latitude,
    required this.longitude,
    required this.type,
    this.importance = 0.0,
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// =============================================================================
//  MAIN
// =============================================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IOT Scooter',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF7C4DFF),
          surface: Color(0xFF161B22),
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const SplashScreen(),
    );
  }
}

// =============================================================================
//  SPLASH SCREEN
// =============================================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.forward();
    });

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const MapPage(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 600),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              ),
            );
          },
          child: Image.asset(
            'assets/logo.png',
            width: 420,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  MAP PAGE
// =============================================================================

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with TickerProviderStateMixin {
  // Design tokens
  static const _kPrimary = Color(0xFF00E5FF);
  static const _kAccent = Color(0xFF7C4DFF);
  static const _kSurface = Color(0xFF161B22);
  static const _kBg = Color(0xFF0D1117);
  static const _kSuccess = Color(0xFF00E676);
  static const _kWarning = Color(0xFFFF9100);
  static const _kDanger = Color(0xFFFF5252);

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

  // Vehicle Data
  int batteryLevel = 85;
  int speed = 0;
  int motorTemp = 45;
  int signalStrength = 4;
  String gpsAccuracy = 'Good';
  String trafficInfo = 'Light';

  // Navigation Data
  double routeDistance = 0;
  int routeDuration = 0;
  String arrivalTime = '';

  // Map Data
  Position? currentPosition;
  LatLng? selectedLocation;
  LocationInfo? selectedLocationInfo;
  List<LatLng> routePoints = [];
  String routeInfo = '';

  // Map Layers
  String currentMapStyle = 'dark';
  final List<MapLayer> availableLayers = [
    MapLayer('dark', 'Koyu', Icons.dark_mode_rounded),
    MapLayer('standard', 'Standart', Icons.map_rounded),
    MapLayer('satellite', 'Uydu', Icons.satellite_alt_rounded),
    MapLayer('terrain', 'Arazi', Icons.terrain_rounded),
  ];

  // Search state
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<SearchResult> _searchResults = [];
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebouncer;

  int _currentStatsPage = 0;

  // ===========================================================================
  //  LIFECYCLE & INITIALIZATION
  // ===========================================================================

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
      debugPrint('Starting...');
      await _checkConnectivity();
      _mapController = MapController();

      if (mounted) {
        setState(() => _isInitializing = false);
        _startEntryAnimations();
        _requestLocationAsync();
      }
      debugPrint('Init complete');
    } catch (e) {
      debugPrint('Init error: $e');
      if (mounted) {
        setState(() => _isInitializing = false);
        _startEntryAnimations();
        _setDefaultLocation();
      }
    }
  }

  // ===========================================================================
  //  CONNECTIVITY
  // ===========================================================================

  void _startEntryAnimations() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _sidebarController.forward();
        _statsTransitionController.forward();
      }
    });
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
          }
        }
      });
    } catch (e) {
      debugPrint('Connectivity check error: $e');
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

  // ===========================================================================
  //  LOCATION
  // ===========================================================================

  void _requestLocationAsync() {
    _locationTimer = Timer(const Duration(milliseconds: 500), () async {
      await _handleLocationPermissions();
    });
  }

  Future<void> _handleLocationPermissions() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setDefaultLocation();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 10));
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        _setDefaultLocation();
        return;
      }

      await _getCurrentLocation();
    } catch (e) {
      debugPrint('Permission error: $e');
      _setDefaultLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;

    try {
      try {
        final lastPosition = await Geolocator.getLastKnownPosition()
            .timeout(const Duration(seconds: 3));

        if (lastPosition != null && mounted) {
          setState(() => currentPosition = lastPosition);
          _moveMapToLocation(lastPosition);
          _getCurrentPositionInBackground();
          return;
        }
      } catch (e) {
        debugPrint('Last position error: $e');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      ).timeout(const Duration(seconds: 15));

      if (mounted) {
        setState(() => currentPosition = position);
        _moveMapToLocation(position);
      }
    } catch (e) {
      debugPrint('Location error: $e');
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
        }
      } catch (e) {
        debugPrint('Background location error: $e');
      }
    });
  }

  void _moveMapToLocation(Position position) {
    if (!_mapReady || _mapController == null || !mounted) return;
    try {
      _mapController!.move(
        LatLng(position.latitude, position.longitude),
        15,
      );
    } catch (e) {
      debugPrint('Map move error: $e');
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
              debugPrint('Default location error: $e');
            }
          }
        });
      }
    }
  }

  void _onMapReady() {
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

  // ===========================================================================
  //  MAP INTERACTIONS
  // ===========================================================================

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
      debugPrint('Location info error: $e');
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

  // ===========================================================================
  //  ROUTING
  // ===========================================================================

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes dk';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '$hours saat';
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
    if (isOfflineMode) return;

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
      debugPrint('Route error: $e');
    } finally {
      if (mounted) {
        setState(() => isGettingRoute = false);
      }
    }
  }

  Future<List<LatLng>> _getOnlineRoute(LatLng start, LatLng end) async {
    final url = 'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson';

    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['routes']?.isNotEmpty == true) {
        final route = data['routes'][0];

        if (route['distance'] != null && route['duration'] != null) {
          routeDistance = (route['distance'] / 1000);
          routeDuration = (route['duration'] / 60).round();
          arrivalTime = _calculateArrivalTime(routeDuration);
        }

        return _decodeGeoJsonRoute(route['geometry']);
      }
    }

    throw Exception('Route not found');
  }

  Future<String> _getRouteInfo(LatLng start, LatLng end, bool online) async {
    if (online && routeDuration > 0 && routeDistance > 0) {
      return '${routeDistance.toStringAsFixed(1)} km  •  ${_formatDuration(routeDuration)}  •  ${arrivalTime}\'de varış';
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

    return '${distance.toStringAsFixed(1)} km  •  ${_formatDuration(time)}  •  ${arrival}\'de varış';
  }

  List<LatLng> _decodeGeoJsonRoute(dynamic geometry) {
    final points = <LatLng>[];
    try {
      if (geometry is Map && geometry['coordinates'] is List) {
        final coords = geometry['coordinates'] as List;
        for (final coord in coords) {
          if (coord is List && coord.length >= 2) {
            final lng = (coord[0] as num).toDouble();
            final lat = (coord[1] as num).toDouble();
            // Validate coordinates
            if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
              points.add(LatLng(lat, lng));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('GeoJSON decode error: $e');
    }
    return points;
  }

  void _fitMapToRoute() {
    if (!_mapReady ||
        routePoints.length < 2 ||
        _mapController == null ||
        !mounted) {
      return;
    }

    try {
      final bounds = LatLngBounds.fromPoints(routePoints);
      _mapController!.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(60),
        ),
      );
    } catch (e) {
      debugPrint('Route fit error: $e');
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
    if (selectedLocation != null) {
      _clearSelection();
    }
  }

  // ===========================================================================
  //  SEARCH
  // ===========================================================================

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
      debugPrint('Search error: $e');
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

  // ===========================================================================
  //  STATUS HELPERS
  // ===========================================================================

  String _getGpsShortStatus() {
    if (gpsAccuracy == 'Mükemmel') return 'A+';
    if (gpsAccuracy == 'İyi') return 'B';
    return 'C';
  }

  Color _getBatteryColor() {
    if (batteryLevel > 60) return _kSuccess;
    if (batteryLevel > 30) return _kWarning;
    return _kDanger;
  }

  Color _getSignalColor() {
    if (signalStrength >= 4) return _kSuccess;
    if (signalStrength >= 3) return _kWarning;
    return _kDanger;
  }

  Color _getGpsColor() {
    if (gpsAccuracy == 'Mükemmel') return _kSuccess;
    if (gpsAccuracy == 'İyi') return _kWarning;
    return _kDanger;
  }

  Color _getTemperatureColor() {
    if (motorTemp > 55) return _kDanger;
    if (motorTemp > 45) return _kWarning;
    return _kSuccess;
  }

  IconData _getBatteryIcon() {
    if (batteryLevel > 80) return Icons.battery_full_rounded;
    if (batteryLevel > 60) return Icons.battery_5_bar_rounded;
    if (batteryLevel > 40) return Icons.battery_4_bar_rounded;
    if (batteryLevel > 20) return Icons.battery_2_bar_rounded;
    return Icons.battery_alert_rounded;
  }

  String _getMapTileUrl(bool isOfflineMode) {
    switch (currentMapStyle) {
      case 'dark':
        return 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
      case 'satellite':
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case 'terrain':
        return 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
      default:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }

  // ===========================================================================
  //  MAP STYLE PICKER
  // ===========================================================================

  void _showMapStylePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kPrimary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.layers_rounded,
                        color: _kPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Harita Stili',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.close_rounded,
                          color: Colors.white.withOpacity(0.4), size: 18),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              color: Colors.white.withOpacity(0.04),
            ),
            const SizedBox(height: 4),
            ...availableLayers.map((layer) {
              final isSelected = currentMapStyle == layer.id;
              return Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _kPrimary.withOpacity(0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _kPrimary.withOpacity(0.15)
                          : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      layer.icon,
                      color: isSelected
                          ? _kPrimary
                          : Colors.white.withOpacity(0.5),
                      size: 20,
                    ),
                  ),
                  title: Text(
                    layer.name,
                    style: TextStyle(
                      color: isSelected ? _kPrimary : Colors.white,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 15,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle_rounded,
                          color: _kPrimary, size: 22)
                      : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onTap: () {
                    setState(() => currentMapStyle = layer.id);
                    _animateMapTransition();
                    Navigator.pop(context);
                  },
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  //  DISPOSE
  // ===========================================================================

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

  // ===========================================================================
  //  UI BUILDER METHODS
  // ===========================================================================

  // ── Glass Icon Button ──
  Widget _buildGlassIconButton(IconData icon, VoidCallback onTap,
      {double size = 38}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Icon(icon, color: Colors.white.withOpacity(0.6), size: size * 0.47),
      ),
    );
  }

  // ── Gradient Action Button ──
  Widget _buildGradientButton({
    required String label,
    IconData? icon,
    bool isLoading = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: onTap != null
              ? const LinearGradient(
                  colors: [_kPrimary, _kAccent],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: onTap == null ? Colors.white.withOpacity(0.06) : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: onTap != null
              ? [
                  BoxShadow(
                    color: _kPrimary.withOpacity(0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else if (icon != null)
              Icon(icon, color: Colors.white, size: 18),
            if (icon != null || isLoading) const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Control Button (right sidebar) ──
  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? color.withOpacity(0.15) : Colors.transparent,
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  // ── Current Location Marker ──
  Marker _buildCurrentLocationMarker(bool isOfflineMode) {
    final color = isOfflineMode ? _kWarning : _kPrimary;
    return Marker(
      point: LatLng(currentPosition!.latitude, currentPosition!.longitude),
      width: 60,
      height: 60,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer ring pulse
              Container(
                width: 60 * (1 + _pulseAnimation.value * 0.4),
                height: 60 * (1 + _pulseAnimation.value * 0.4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        color.withOpacity(0.4 * (1 - _pulseAnimation.value)),
                    width: 1.5,
                  ),
                ),
              ),
              // Middle glow
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.12),
                ),
              ),
              // Core dot
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.6),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Selected Location Marker ──
  Marker _buildSelectedLocationMarker(bool isOfflineMode) {
    final color = isOfflineMode ? _kDanger : _kAccent;
    return Marker(
      point: selectedLocation!,
      width: 48,
      height: 48,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.5),
              blurRadius: 14,
              spreadRadius: 3,
            ),
          ],
        ),
        child: const Icon(Icons.place_rounded, color: Colors.white, size: 24),
      ),
    );
  }

  // ── Top Bar (Search or Route) ──
  Widget _buildTopBar(bool isOfflineMode) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 580),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: isOfflineMode
              ? (routeInfo.isNotEmpty
                  ? _buildRouteInfoBar()
                  : _buildOfflineBanner())
              : (routeInfo.isNotEmpty
                  ? _buildRouteInfoBar()
                  : _buildSearchBar()),
        ),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kWarning.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, color: _kWarning, size: 18),
          const SizedBox(width: 10),
          Text(
            'Çevrimdışı Mod',
            style: TextStyle(
              color: _kWarning.withOpacity(0.9),
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Route Info Bar ──
  Widget _buildRouteInfoBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kPrimary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
          ),
          BoxShadow(
            color: _kPrimary.withOpacity(0.08),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.navigation_rounded,
                color: _kPrimary, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              routeInfo,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w500,
                fontSize: 14,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildGlassIconButton(Icons.close_rounded, _clearRoute, size: 34),
        ],
      ),
    );
  }

  // ── Search Bar ──
  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'Konum ara...',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.25),
                fontSize: 15,
                fontWeight: FontWeight.w300,
              ),
              prefixIcon: _isSearching
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(_kPrimary),
                          backgroundColor: Colors.white.withOpacity(0.06),
                        ),
                      ),
                    )
                  : Icon(Icons.search_rounded,
                      color: Colors.white.withOpacity(0.3), size: 22),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: Colors.white.withOpacity(0.3), size: 20),
                      onPressed: _clearSearch,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
            cursorColor: _kPrimary,
            onSubmitted: _searchLocation,
            onChanged: _onSearchChanged,
          ),
          // Search Results
          if (_searchResults.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.04)),
                ),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final result = _searchResults[index];
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _goToSearchResult(result),
                      borderRadius: BorderRadius.circular(12),
                      splashColor: _kPrimary.withOpacity(0.08),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: _kPrimary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.place_rounded,
                                  color: _kPrimary, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    result.shortName.isNotEmpty
                                        ? result.shortName
                                        : result.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (result.type.isNotEmpty)
                                    Text(
                                      result.type,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.35),
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios_rounded,
                                color: Colors.white.withOpacity(0.15),
                                size: 14),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ── Right Controls ──
  Widget _buildRightControls(bool isOfflineMode) {
    return Positioned(
      right: 20,
      top: MediaQuery.of(context).padding.top + 100,
      child: SlideTransition(
        position: _sidebarSlideAnimation,
        child: Container(
          decoration: BoxDecoration(
            color: _kSurface.withOpacity(0.9),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 20,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildControlButton(
                icon: isOfflineMode
                    ? Icons.wifi_off_rounded
                    : Icons.wifi_rounded,
                color: isOfflineMode ? _kWarning : _kPrimary,
                onTap: _toggleOfflineMode,
                isActive: isOfflineMode,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(
                  width: 24,
                  height: 1,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
              _buildControlButton(
                icon: Icons.my_location_rounded,
                color: _kPrimary,
                onTap: _getCurrentLocation,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(
                  width: 24,
                  height: 1,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
              _buildControlButton(
                icon: Icons.layers_rounded,
                color: _kSuccess,
                onTap: _showMapStylePicker,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom HUD ──
  Widget _buildBottomHUD(bool isOfflineMode) {
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: _statsTransitionController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, (1 - _statsSlideAnimation.value) * 80),
              child: Opacity(
                opacity: _statsOpacityAnimation.value,
                child: child,
              ),
            );
          },
          child: Container(
            constraints: const BoxConstraints(maxWidth: 820),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: _kSurface.withOpacity(0.92),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildHudStat(
                  icon: Icons.speed_rounded,
                  value: '$speed',
                  unit: 'km/h',
                  color: isNavigating ? _kSuccess : Colors.white.withOpacity(0.35),
                ),
                _buildHudDivider(),
                _buildHudStat(
                  icon: _getBatteryIcon(),
                  value: '$batteryLevel',
                  unit: '%',
                  color: _getBatteryColor(),
                ),
                _buildHudDivider(),
                _buildHudStat(
                  icon: Icons.thermostat_rounded,
                  value: '$motorTemp',
                  unit: '°C',
                  color: _getTemperatureColor(),
                ),
                _buildHudDivider(),
                _buildHudStat(
                  icon: Icons.signal_cellular_alt_rounded,
                  value: '$signalStrength',
                  unit: '/5',
                  color: _getSignalColor(),
                ),
                _buildHudDivider(),
                _buildHudStat(
                  icon: Icons.gps_fixed_rounded,
                  value: _getGpsShortStatus(),
                  unit: 'GPS',
                  color: _getGpsColor(),
                ),
                _buildHudDivider(),
                _buildHudStat(
                  icon: isOfflineMode
                      ? Icons.wifi_off_rounded
                      : Icons.wifi_rounded,
                  value: isOfflineMode ? 'OFF' : 'ON',
                  unit: 'Net',
                  color: isOfflineMode ? _kWarning : _kPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHudStat({
    required IconData icon,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(height: 5),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              unit,
              style: TextStyle(
                color: color.withOpacity(0.45),
                fontSize: 10,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHudDivider() {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: Colors.white.withOpacity(0.05),
    );
  }

  // ── Location Card ──
  Widget _buildLocationCard(bool isOfflineMode) {
    final accentColor = isOfflineMode ? _kWarning : _kPrimary;

    return AnimatedBuilder(
      animation: _locationCardController,
      builder: (context, child) {
        return Positioned(
          left: 24,
          bottom: 110,
          child: Transform.translate(
            offset: Offset(0, (1 - _locationCardController.value) * 200),
            child: Opacity(
              opacity: _locationCardController.value,
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _kSurface.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(22),
                  border:
                      Border.all(color: accentColor.withOpacity(0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 30,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: accentColor.withOpacity(0.05),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isOfflineMode
                                ? Icons.location_pin
                                : Icons.place_rounded,
                            color: accentColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedLocationInfo?.name ??
                                    'Konum Yükleniyor...',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (selectedLocationInfo
                                      ?.category.isNotEmpty ==
                                  true)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    selectedLocationInfo!.category,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: accentColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        _buildGlassIconButton(
                            Icons.close_rounded, _hideLocationCard,
                            size: 34),
                      ],
                    ),
                    if (selectedLocationInfo != null) ...[
                      // Divider
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Container(
                          height: 1,
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                      // Address
                      if (selectedLocationInfo!.address.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            selectedLocationInfo!.address,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      // Coordinates
                      Row(
                        children: [
                          Icon(Icons.tag_rounded,
                              color: Colors.white.withOpacity(0.2),
                              size: 14),
                          const SizedBox(width: 6),
                          Text(
                            selectedLocationInfo!.coordinates,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      // Actions
                      if (!isOfflineMode)
                        Row(
                          children: [
                            Expanded(
                              child: _buildGradientButton(
                                label: isGettingRoute
                                    ? 'Hesaplanıyor...'
                                    : 'Rota Hesapla',
                                icon: isGettingRoute
                                    ? null
                                    : Icons.navigation_rounded,
                                isLoading: isGettingRoute,
                                onTap:
                                    isGettingRoute ? null : _calculateRoute,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _buildGlassIconButton(
                                Icons.close_rounded, _clearSelection,
                                size: 46),
                          ],
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _kWarning.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: _kWarning.withOpacity(0.12)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.wifi_off_rounded,
                                  color: _kWarning.withOpacity(0.7),
                                  size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Çevrimdışı — sadece koordinat bilgisi',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _kWarning.withOpacity(0.6),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _clearSelection,
                                child: Icon(Icons.close_rounded,
                                    color: _kWarning.withOpacity(0.4),
                                    size: 16),
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
        );
      },
    );
  }

  // ===========================================================================
  //  BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    // Loading State
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: _kBg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: const AlwaysStoppedAnimation<Color>(_kPrimary),
                  backgroundColor: Colors.white.withOpacity(0.04),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'HARİTA YÜKLENİYOR',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withOpacity(0.35),
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isOfflineMode = forceOffline || !isOnline;

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // ── MAP ──
          Positioned.fill(
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
                // Route line
                if (routePoints.length >= 2 && !isOfflineMode)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        strokeWidth: 4.5,
                        color: _kPrimary,
                        borderStrokeWidth: 3,
                        borderColor: _kPrimary.withOpacity(0.25),
                      ),
                    ],
                  ),
                // Markers
                MarkerLayer(
                  markers: [
                    if (currentPosition != null)
                      _buildCurrentLocationMarker(isOfflineMode),
                    if (selectedLocation != null)
                      _buildSelectedLocationMarker(isOfflineMode),
                  ],
                ),
              ],
            ),
          ),

          // ── TOP BAR ──
          _buildTopBar(isOfflineMode),

          // ── RIGHT CONTROLS ──
          _buildRightControls(isOfflineMode),

          // ── BOTTOM HUD ──
          _buildBottomHUD(isOfflineMode),

          // ── LOCATION CARD ──
          if (showLocationCard) _buildLocationCard(isOfflineMode),
        ],
      ),
    );
  }
}

// =============================================================================
//  MODELS
// =============================================================================

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

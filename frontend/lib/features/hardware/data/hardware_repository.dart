import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

final hardwareRepositoryProvider = Provider<HardwareRepository>(
  (ref) => HardwareRepository(ref.watch(dioProvider)),
);

/// Printer status as the print agent reports it.
abstract class PrinterStatus {
  static const ready = 'READY';
  static const paperLow = 'PAPER_LOW';
  static const offline = 'OFFLINE';
}

class Printer {
  const Printer({
    required this.id,
    required this.name,
    required this.connection,
    this.host,
    this.port,
    this.paperWidth = 80,
    this.status,
    this.lastError,
  });

  final String id;
  final String name;

  /// LAN, USB or BLUETOOTH.
  final String connection;
  final String? host;
  final int? port;

  /// Paper width in millimetres (58 or 80).
  final int paperWidth;
  final String? status;

  /// Message from the last failed test or print job, if any.
  final String? lastError;

  factory Printer.fromJson(Map j) => Printer(
        id: j['id'] as String,
        name: j['name'] as String,
        connection: j['connection'] as String? ?? 'LAN',
        host: j['host'] as String?,
        port: (j['port'] as num?)?.toInt(),
        paperWidth: (j['paperWidth'] as num?)?.toInt() ?? 80,
        status: j['status'] as String?,
        lastError: j['lastError'] as String?,
      );
}

/// Ticket routing: which printer gets tickets for a station, and its fallback.
class StationRoute {
  const StationRoute({required this.station, this.printerId, this.fallbackPrinterId});

  final String station;
  final String? printerId;
  final String? fallbackPrinterId;

  factory StationRoute.fromJson(Map j) => StationRoute(
        station: j['station'] as String,
        printerId: j['printerId'] as String?,
        fallbackPrinterId: j['fallbackPrinterId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'station': station,
        'printerId': printerId,
        'fallbackPrinterId': fallbackPrinterId,
      };
}

class HardwareRepository {
  HardwareRepository(this._dio);
  final Dio _dio;

  static List<Map> _rows(dynamic body) {
    final raw = body is Map ? (body['data'] ?? body['items']) : body;
    return (raw as List).cast<Map>();
  }

  Future<List<Printer>> printers() async {
    final res = await _dio.get('/printers');
    return _rows(res.data).map(Printer.fromJson).toList();
  }

  Future<Printer> createPrinter(Map<String, dynamic> body) async {
    final res = await _dio.post('/printers', data: body);
    return Printer.fromJson(res.data as Map);
  }

  Future<void> updatePrinter(String id, Map<String, dynamic> body) =>
      _dio.patch('/printers/$id', data: body);

  Future<void> deletePrinter(String id) => _dio.delete('/printers/$id');

  /// Queues a TEST job. The result arrives later through the print agent.
  Future<void> testPrinter(String id) => _dio.post('/printers/$id/test');

  Future<List<StationRoute>> stationRoutes() async {
    final res = await _dio.get('/station-routes');
    return _rows(res.data).map(StationRoute.fromJson).toList();
  }

  Future<void> saveStationRoutes(List<StationRoute> routes) =>
      _dio.put('/station-routes', data: {'items': [for (final r in routes) r.toJson()]});
}

final printersProvider = FutureProvider<List<Printer>>(
  (ref) => ref.watch(hardwareRepositoryProvider).printers(),
);

final stationRoutesProvider = FutureProvider<List<StationRoute>>(
  (ref) => ref.watch(hardwareRepositoryProvider).stationRoutes(),
);

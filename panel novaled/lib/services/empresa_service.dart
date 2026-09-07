import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/empresa_model.dart';
import '../models/plan_model.dart';
import '../models/pago_model.dart';
import '../models/log_auditoria_model.dart';
import 'api_service.dart';

class EmpresaService extends ChangeNotifier {
  static final EmpresaService instance = EmpresaService._internal();
  EmpresaService._internal();

  factory EmpresaService() => instance;

  final _uuid = const Uuid();
  Timer? _liveRefreshTimer;

  List<EmpresaModel> _empresas = [];
  List<PlanModel> _planes = [];
  List<PagoModel> _pagos = [];
  List<LogAuditoriaModel> _logs = [];

  bool _isLoading = true;
  String _filtroTexto = '';
  String _filtroEstado = 'todos'; // 'todos', 'free', 'pro', 'trial', 'por_vencer', 'suspendido'

  List<EmpresaModel> get empresas => _empresas;
  List<PlanModel> get planes => _planes;
  List<PagoModel> get pagos => _pagos;
  List<LogAuditoriaModel> get logs => _logs;
  bool get isLoading => _isLoading;
  String get filtroTexto => _filtroTexto;
  String get filtroEstado => _filtroEstado;

  // Filtrado reactivo
  List<EmpresaModel> get empresasFiltradas {
    return _empresas.where((e) {
      if (_filtroEstado == 'eliminado') {
        if (!e.estaEliminado) return false;
      } else {
        if (e.estaEliminado) return false;
      }

      // Filtro de Texto
      final q = _filtroTexto.toLowerCase().trim();
      final matchTexto = q.isEmpty ||
          e.nombreComercial.toLowerCase().contains(q) ||
          e.codigoEmpresa.toLowerCase().contains(q) ||
          e.emailContacto.toLowerCase().contains(q) ||
          e.nitRut.toLowerCase().contains(q) ||
          e.ciudad.toLowerCase().contains(q);

      if (!matchTexto) return false;

      // Filtro de Estado / Plan
      switch (_filtroEstado) {
        case 'free':
          return e.esFree && !e.estaSuspendido;
        case 'pro':
          return e.esPro && !e.estaSuspendido && !e.esTrial;
        case 'trial':
          return e.esTrial && !e.estaSuspendido;
        case 'por_vencer':
          return e.estaPorVencer;
        case 'suspendido':
          return e.estaSuspendido;
        case 'eliminado':
          return e.estaEliminado;
        default:
          return true;
      }
    }).toList();
  }

  // KPIs
  int get totalEmpresasActivas => _empresas.where((e) => !e.estaEliminado && !e.estaSuspendido).length;
  int get totalFree => _empresas.where((e) => !e.estaEliminado && e.esFree).length;
  int get totalPro => _empresas.where((e) => !e.estaEliminado && e.esPro && !e.esTrial).length;
  int get totalTrials => _empresas.where((e) => !e.estaEliminado && e.esTrial).length;
  int get totalPorVencer => _empresas.where((e) => !e.estaEliminado && e.estaPorVencer).length;
  int get totalSuspendidas => _empresas.where((e) => !e.estaEliminado && e.estaSuspendido).length;
  int get totalEliminadas => _empresas.where((e) => e.estaEliminado).length;

  int get totalCotizacionesGlobal => _empresas.fold(0, (sum, e) => sum + (e.estaEliminado ? 0 : e.totalCotizaciones));
  int get totalPuntoVentaGlobal => _empresas.fold(0, (sum, e) => sum + (e.estaEliminado ? 0 : e.totalPuntoVenta));
  int get totalDocumentosGlobal => _empresas.fold(0, (sum, e) => sum + (e.estaEliminado ? 0 : (e.totalCotizaciones + e.totalPuntoVenta)));

  double get ingresosRecurrentesMRR {
    double total = 0.0;
    for (var e in _empresas) {
      if (!e.estaEliminado && !e.estaSuspendido && e.esPro && !e.esTrial) {
        final plan = getPlanById(e.planId);
        if (plan != null) {
          if (plan.id == 'pro_anual') {
            total += (plan.precio / 12);
          } else {
            total += plan.precio;
          }
        }
      }
    }
    return total;
  }

  PlanModel? getPlanById(String planId) {
    final clean = planId.toLowerCase().trim();
    try {
      return _planes.firstWhere(
        (p) => p.id.toLowerCase() == clean ||
               (clean.contains('plus') && p.id == 'plus') ||
               (clean.contains('pro') && p.id == 'pro' && !clean.contains('plus')) ||
               ((clean == 'free' || clean == 'gratis') && p.id == 'free'),
      );
    } catch (_) {
      if (clean.contains('plus')) return PlanModel.planPlusDefault;
      if (clean.contains('pro')) return PlanModel.planProDefault;
      return PlanModel.planFreeDefault;
    }
  }

  EmpresaModel? getEmpresaById(String id) {
    try {
      return _empresas.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  void setFiltroTexto(String val) {
    _filtroTexto = val;
    notifyListeners();
  }

  void setFiltroEstado(String estado) {
    _filtroEstado = estado;
    notifyListeners();
  }

  bool _isOnline = false;
  bool get isOnline => _isOnline;

  String resolverTenantKey(EmpresaModel e) {
    final email = e.emailContacto.toLowerCase().trim();
    final name = e.nombreComercial.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (email.contains('novaled') || name.contains('novaled')) {
      return 'novaled';
    }
    if (email.contains('ultrashop') || name.contains('ultrashop')) {
      return 'tenant_ultrashop';
    }
    if (email.contains('unithor') || name.contains('unithor')) {
      return 'tenant_unithor';
    }
    return 'tenant_$name';
  }

  Future<void> sincronizarEstadisticasEnVivo() async {
    try {
      final liveData = await ApiService.fetchLiveTenantStats();
      if (liveData == null || liveData['success'] != true) return;

      final stats = liveData['stats'] as Map<String, dynamic>? ?? {};
      final users = (liveData['users'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

      bool hasChanges = false;

      // 1. Descubrir nuevas empresas registradas en MySQL
      for (var u in users) {
        final username = u['username'].toString().toLowerCase().trim();
        if (username.contains('@') && username != 'novaled.elektroshop@gmail.com') {
          final exists = _empresas.any((e) => e.emailContacto.toLowerCase() == username);
          if (!exists) {
            final nombre = username.split('@')[0];
            _empresas.add(
              EmpresaModel(
                id: 'emp-$nombre',
                codigoEmpresa: 'NOV-${(_empresas.length + 1).toString().padLeft(3, '0')}',
                nombreComercial: nombre,
                razonSocial: '$nombre S.R.L.',
                emailContacto: username,
                telefono: '',
                planId: 'free',
                estado: 'activo_free',
                fechaRegistro: DateTime.now(),
                fechaInicioPlan: DateTime.now(),
                usuariosActivos: 1,
              ),
            );
            hasChanges = true;
          }
        }
      }

      // 2. Mapear estadísticas por empresa
      for (int i = 0; i < _empresas.length; i++) {
        final e = _empresas[i];
        final tKey = resolverTenantKey(e);

        if (stats.containsKey(tKey)) {
          final s = stats[tKey] as Map<String, dynamic>;
          final totalCot = (s['total_cotizaciones'] as num?)?.toInt() ?? 0;
          final totalNv = (s['total_notas_venta'] as num?)?.toInt() ?? 0;
          final totalNe = (s['total_notas_entrega'] as num?)?.toInt() ?? 0;
          final totalProf = (s['total_proformas'] as num?)?.toInt() ?? 0;
          final totalPv = (s['total_punto_venta'] as num?)?.toInt() ?? (totalNv + totalNe);
          final totalEsc = (s['total_escaneos'] as num?)?.toInt() ?? 0;
          final totalUsr = (s['total_usuarios'] as num?)?.toInt() ?? e.usuariosActivos;
          final docsMes = (s['documentos_mes_actual'] as num?)?.toInt() ?? 0;
          final arts = (s['total_articulos'] as num?)?.toInt() ?? e.articulosCreados;
          final ultActStr = s['ultima_actividad']?.toString();
          final ultAct = ultActStr != null ? DateTime.tryParse(ultActStr) : e.ultimaActividad;

          if (e.totalCotizaciones != totalCot ||
              e.totalNotasVenta != totalNv ||
              e.totalNotasEntrega != totalNe ||
              e.totalProformas != totalProf ||
              e.totalPuntoVenta != totalPv ||
              e.totalEscaneos != totalEsc ||
              e.usuariosActivos != totalUsr ||
              e.documentosMesActual != docsMes ||
              e.articulosCreados != arts) {
            _empresas[i] = e.copyWith(
              totalCotizaciones: totalCot,
              totalNotasVenta: totalNv,
              totalNotasEntrega: totalNe,
              totalProformas: totalProf,
              totalPuntoVenta: totalPv,
              totalEscaneos: totalEsc,
              usuariosActivos: totalUsr,
              documentosMesActual: docsMes,
              articulosCreados: arts,
              ultimaActividad: ultAct ?? e.ultimaActividad,
            );
            hasChanges = true;
          }
        }
      }

      if (hasChanges) {
        await _guardarEmpresas();
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error sincronizando estadísticas en vivo: $e");
    }
  }

  Future<void> inicializar() async {
    _isLoading = true;
    notifyListeners();

    // 1. Conectar con el servidor online MySQL
    _isOnline = await ApiService.loginSuperadmin();

    final prefs = await SharedPreferences.getInstance();

    // Limpieza forzada de versiones antiguas de caché
    final cacheVersion = prefs.getString('panel_storage_version');
    if (cacheVersion != 'v4_official_plans_joel') {
      await prefs.remove('panel_empresas');
      await prefs.remove('panel_planes');
      await prefs.remove('panel_pagos');
      await prefs.remove('panel_logs');
      await prefs.setString('panel_storage_version', 'v4_official_plans_joel');
    }

    final empresasJson = prefs.getString('panel_empresas');
    final planesJson = prefs.getString('panel_planes');
    final pagosJson = prefs.getString('panel_pagos');
    final logsJson = prefs.getString('panel_logs');

    if (planesJson != null) {
      final List list = jsonDecode(planesJson);
      _planes = list.map((m) => PlanModel.fromMap(m)).toList();
    } else {
      _planes = [
        PlanModel.planFreeDefault,
        PlanModel.planProDefault,
        PlanModel.planPlusDefault,
      ];
      await _guardarPlanes();
    }

    if (empresasJson != null) {
      final List list = jsonDecode(empresasJson);
      _empresas = list.map((m) => EmpresaModel.fromMap(m)).toList();
      if (_empresas.isEmpty) {
        _cargarEmpresasDemo();
      }
    } else {
      _cargarEmpresasDemo();
    }

    // Sincronizar estadísticas iniciales en vivo
    if (_isOnline) {
      await sincronizarEstadisticasEnVivo();
    }

    // Iniciar timer de sincronización periódica en tiempo real (cada 4s)
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      sincronizarEstadisticasEnVivo();
    });

    await _guardarEmpresas();

    if (pagosJson != null) {
      final List list = jsonDecode(pagosJson);
      _pagos = list.map((m) => PagoModel.fromMap(m)).toList();
      if (_pagos.isEmpty) {
        _cargarPagosDemo();
      }
      await _guardarPagos();
    } else {
      _cargarPagosDemo();
      await _guardarPagos();
    }

    if (logsJson != null) {
      final List list = jsonDecode(logsJson);
      _logs = list.map((m) => LogAuditoriaModel.fromMap(m)).toList();
    } else {
      _logs = [
        LogAuditoriaModel(
          id: _uuid.v4(),
          empresaId: 'emp-001',
          empresaNombre: 'Novaled Iluminación Central (Joel)',
          usuarioSuperadmin: 'SuperAdmin Novaled',
          accion: 'INICIO_SISTEMA',
          descripcion: 'Panel conectado en tiempo real al servidor online novaledbolivia.com con la cuenta oficial novaled.elektroshop@gmail.com.',
          fecha: DateTime.now().subtract(const Duration(days: 30)),
        ),
      ];
      await _guardarLogs();
    }

    // Actualizar estados automáticos por fecha
    _recalcularEstadosAutomaticos();

    _isLoading = false;
    notifyListeners();
  }

  void _recalcularEstadosAutomaticos() {
    for (int i = 0; i < _empresas.length; i++) {
      final e = _empresas[i];
      if (e.estaEliminado || e.esFree) continue;

      if (e.fechaVencimiento != null) {
        final dias = e.diasRestantes;
        if (dias < -e.diasGracia && e.estado != 'suspendido') {
          _empresas[i] = e.copyWith(estado: 'suspendido');
        } else if (dias < 0 && dias >= -e.diasGracia && e.estado != 'gracia') {
          _empresas[i] = e.copyWith(estado: 'gracia');
        } else if (dias >= 0 && dias <= 5 && e.estado == 'activo_pro') {
          _empresas[i] = e.copyWith(estado: 'por_vencer');
        }
      }
    }
  }

  void _cargarEmpresasDemo() {
    final now = DateTime.now();
    _empresas = [
      EmpresaModel(
        id: 'emp-001',
        codigoEmpresa: 'NOV-001',
        nombreComercial: 'Novaled Iluminación Central (Joel)',
        razonSocial: 'Novaled Bolivia S.R.L.',
        nitRut: '1029384021',
        telefono: '+591 78945612',
        emailContacto: 'novaled.elektroshop@gmail.com',
        direccionPrincipal: 'C. Isaac Tamayo #840 La Paz - Bolivia',
        ciudad: 'La Paz',
        pais: 'Bolivia',
        monedaSimbolo: 'Bs.',
        planId: 'plus',
        estado: 'activo_pro',
        fechaRegistro: now.subtract(const Duration(days: 120)),
        fechaInicioPlan: now.subtract(const Duration(days: 120)),
        fechaVencimiento: now.add(const Duration(days: 245)),
        documentosMesActual: 180,
        sucursalesActivas: 2,
        usuariosActivos: 5,
        articulosCreados: 340,
        colorMarca: '#F5C842',
        notasAdmin: 'Cuenta principal de Joel. Acceso PRO ilimitado para él y todo su equipo de vendedores.',
      ),
    ];
  }

  void _cargarPagosDemo() {
    final now = DateTime.now();
    _pagos = [
      PagoModel(
        id: 'pag-001',
        empresaId: 'emp-001',
        empresaNombre: 'Novaled Iluminación Central (Joel)',
        monto: 1500.0,
        moneda: 'Bs',
        planId: 'pro_anual',
        planNombre: 'Plan PRO Anual',
        mesesPagados: 12,
        metodoPago: 'Transferencia Bancaria',
        referenciaTransaccion: 'TRF-BMSC-98124',
        fechaPago: now.subtract(const Duration(days: 120)),
        fechaCoberturaDesde: now.subtract(const Duration(days: 120)),
        fechaCoberturaHasta: now.add(const Duration(days: 245)),
        registradoPor: 'SuperAdmin Novaled',
      ),
    ];
  }

  // --- MÉTODOS CRUD EMPRESAS ---

  Future<void> crearEmpresa({
    required String nombreComercial,
    String razonSocial = '',
    String nitRut = '',
    String telefono = '',
    required String emailContacto,
    String direccionPrincipal = '',
    String ciudad = 'La Paz',
    String pais = 'Bolivia',
    String monedaSimbolo = 'Bs.',
    required String planId,
    bool esTrial = false,
    int diasTrial = 14,
    int mesesPago = 1,
    String metodoPago = 'Transferencia Bancaria',
    String referenciaPago = '',
    String colorMarca = '#F5C842',
    String notasAdmin = '',
    String? usuarioAdmin,
    String? passwordAdmin,
    String rolUsuario = 'admin',
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final codigo = 'NOV-${(_empresas.length + 1).toString().padLeft(3, '0')}';

    DateTime? fechaVencimiento;
    String estado = 'activo_free';

    if (planId == 'free') {
      estado = 'activo_free';
      fechaVencimiento = null;
    } else if (esTrial) {
      estado = 'trial_pro';
      fechaVencimiento = now.add(Duration(days: diasTrial));
    } else {
      estado = 'activo_pro';
      fechaVencimiento = now.add(Duration(days: 30 * mesesPago));
    }

    final nuevaEmpresa = EmpresaModel(
      id: id,
      codigoEmpresa: codigo,
      nombreComercial: nombreComercial,
      razonSocial: razonSocial,
      nitRut: nitRut,
      telefono: telefono,
      emailContacto: emailContacto,
      direccionPrincipal: direccionPrincipal,
      ciudad: ciudad,
      pais: pais,
      monedaSimbolo: monedaSimbolo,
      planId: planId,
      estado: estado,
      fechaRegistro: now,
      fechaInicioPlan: now,
      fechaVencimiento: fechaVencimiento,
      colorMarca: colorMarca,
      notasAdmin: notasAdmin,
      usuariosActivos: usuarioAdmin != null && usuarioAdmin.isNotEmpty ? 1 : 0,
    );

    _empresas.insert(0, nuevaEmpresa);
    await _guardarEmpresas();

    // Sincronizar credenciales de usuario en el servidor online MySQL
    if (passwordAdmin != null && passwordAdmin.trim().isNotEmpty) {
      final passHash = sha256.convert(utf8.encode(passwordAdmin.trim())).toString();
      final users = await ApiService.fetchLiveUsers();
      
      final aliases = <String>{};
      if (usuarioAdmin != null && usuarioAdmin.trim().isNotEmpty) {
        aliases.add(usuarioAdmin.trim().toLowerCase());
      }
      if (emailContacto.trim().isNotEmpty) {
        aliases.add(emailContacto.trim().toLowerCase());
      }
      final cleanName = nombreComercial.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (cleanName.isNotEmpty) {
        aliases.add(cleanName);
      }

      for (final alias in aliases) {
        final idx = users.indexWhere((u) => u['username'].toString().toLowerCase() == alias);
        if (idx != -1) {
          users[idx]['passwordHash'] = passHash;
          users[idx]['role'] = rolUsuario;
        } else {
          users.add({
            'username': alias,
            'passwordHash': passHash,
            'role': rolUsuario,
            'createdAt': DateTime.now().toIso8601String(),
          });
        }
      }
      await ApiService.saveLiveUsers(users);
    }

    // Si hubo pago directo, registrar en pagos
    if (planId != 'free' && !esTrial) {
      final plan = getPlanById(planId);
      final montoTotal = (plan?.precio ?? 150.0) * mesesPago;

      final nuevoPago = PagoModel(
        id: _uuid.v4(),
        empresaId: id,
        empresaNombre: nombreComercial,
        monto: montoTotal,
        moneda: monedaSimbolo,
        planId: planId,
        planNombre: plan?.nombre ?? 'Plan PRO',
        mesesPagados: mesesPago,
        metodoPago: metodoPago,
        referenciaTransaccion: referenciaPago.isNotEmpty ? referenciaPago : 'REG-INICIAL-$codigo',
        fechaPago: now,
        fechaCoberturaDesde: now,
        fechaCoberturaHasta: fechaVencimiento!,
        registradoPor: 'SuperAdmin Novaled',
      );
      _pagos.insert(0, nuevoPago);
      await _guardarPagos();
    }

    await registrarLog(
      empresaId: id,
      empresaNombre: nombreComercial,
      accion: 'CREAR_EMPRESA',
      descripcion: 'Empresa "$nombreComercial" creada bajo plan $planId. Usuario inicial: "${usuarioAdmin ?? 'N/A'}" con acceso online.',
    );

    notifyListeners();
  }

  Future<bool> cambiarPasswordEmpresa({
    required String empresaId,
    required String empresaNombre,
    required String emailContacto,
    required String nuevaPassword,
  }) async {
    try {
      if (nuevaPassword.trim().isEmpty) return false;
      final passHash = sha256.convert(utf8.encode(nuevaPassword.trim())).toString();
      final users = await ApiService.fetchLiveUsers();

      final aliases = <String>{
        emailContacto.trim().toLowerCase(),
        empresaNombre.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ''),
      };

      for (final alias in aliases) {
        if (alias.isEmpty) continue;
        final idx = users.indexWhere((u) => u['username'].toString().toLowerCase() == alias);
        if (idx != -1) {
          users[idx]['passwordHash'] = passHash;
        } else {
          users.add({
            'username': alias,
            'passwordHash': passHash,
            'role': 'admin',
            'createdAt': DateTime.now().toIso8601String(),
          });
        }
      }

      final success = await ApiService.saveLiveUsers(users);
      if (success) {
        await registrarLog(
          empresaId: empresaId,
          empresaNombre: empresaNombre,
          accion: 'CAMBIAR_PASSWORD',
          descripcion: 'Contraseña actualizada en el servidor MySQL para la empresa "$empresaNombre" ($emailContacto).',
        );
      }
      return success;
    } catch (e) {
      debugPrint("[ERROR] Error cambiando contraseña: $e");
      return false;
    }
  }

  Future<void> actualizarEmpresa(EmpresaModel empresaActualizada) async {
    final idx = _empresas.indexWhere((e) => e.id == empresaActualizada.id);
    if (idx != -1) {
      _empresas[idx] = empresaActualizada;
      await _guardarEmpresas();

      await registrarLog(
        empresaId: empresaActualizada.id,
        empresaNombre: empresaActualizada.nombreComercial,
        accion: 'EDITAR_EMPRESA',
        descripcion: 'Datos de la empresa "${empresaActualizada.nombreComercial}" actualizados.',
      );

      notifyListeners();
    }
  }

  Future<void> cambiarPlan({
    required String empresaId,
    required String nuevoPlanId,
    int meses = 1,
    bool esTrial = false,
    int diasTrial = 14,
    String metodoPago = 'Transferencia Bancaria',
    String referenciaPago = '',
  }) async {
    final idx = _empresas.indexWhere((e) => e.id == empresaId);
    if (idx == -1) return;

    final e = _empresas[idx];
    final now = DateTime.now();
    DateTime? nuevaFechaVenc;
    String nuevoEstado;

    if (nuevoPlanId == 'free') {
      nuevoEstado = 'activo_free';
      nuevaFechaVenc = null;
    } else if (esTrial) {
      nuevoEstado = 'trial_pro';
      nuevaFechaVenc = now.add(Duration(days: diasTrial));
    } else {
      nuevoEstado = 'activo_pro';
      final base = (e.fechaVencimiento != null && e.fechaVencimiento!.isAfter(now)) ? e.fechaVencimiento! : now;
      nuevaFechaVenc = base.add(Duration(days: 30 * meses));
    }

    _empresas[idx] = e.copyWith(
      planId: nuevoPlanId,
      estado: nuevoEstado,
      fechaVencimiento: nuevaFechaVenc,
    );
    await _guardarEmpresas();

    // Sincronizar plan_id con MySQL en tiempo real
    final tKey = resolverTenantKey(e);
    await ApiService.uploadTenantSettings(
      tenantKey: tKey,
      settings: {'plan_id': nuevoPlanId},
    );

    if (nuevoPlanId != 'free' && !esTrial) {
      final plan = getPlanById(nuevoPlanId);
      final montoTotal = (plan?.precio ?? 150.0) * meses;

      final nuevoPago = PagoModel(
        id: _uuid.v4(),
        empresaId: e.id,
        empresaNombre: e.nombreComercial,
        monto: montoTotal,
        moneda: e.monedaSimbolo,
        planId: nuevoPlanId,
        planNombre: plan?.nombre ?? 'Plan PRO',
        mesesPagados: meses,
        metodoPago: metodoPago,
        referenciaTransaccion: referenciaPago.isNotEmpty ? referenciaPago : 'UPGRADE-${DateTime.now().millisecondsSinceEpoch}',
        fechaPago: now,
        fechaCoberturaDesde: now,
        fechaCoberturaHasta: nuevaFechaVenc!,
        registradoPor: 'SuperAdmin Novaled',
      );
      _pagos.insert(0, nuevoPago);
      await _guardarPagos();
    }

    await registrarLog(
      empresaId: e.id,
      empresaNombre: e.nombreComercial,
      accion: 'CAMBIO_PLAN',
      descripcion: 'Plan cambiado a "$nuevoPlanId". Vencimiento: ${nuevaFechaVenc?.toString().split(' ')[0] ?? 'N/A'}.',
    );

    notifyListeners();
  }

  Future<void> extenderProrroga(String empresaId, int diasExtras) async {
    final idx = _empresas.indexWhere((e) => e.id == empresaId);
    if (idx == -1) return;

    final e = _empresas[idx];
    final now = DateTime.now();
    final base = (e.fechaVencimiento != null && e.fechaVencimiento!.isAfter(now)) ? e.fechaVencimiento! : now;
    final nuevaFecha = base.add(Duration(days: diasExtras));

    _empresas[idx] = e.copyWith(
      fechaVencimiento: nuevaFecha,
      estado: e.esTrial ? 'trial_pro' : 'activo_pro',
    );
    await _guardarEmpresas();

    await registrarLog(
      empresaId: e.id,
      empresaNombre: e.nombreComercial,
      accion: 'PRORROGA_FECHA',
      descripcion: 'Prórroga de +$diasExtras días otorgada. Nuevo vencimiento: ${nuevaFecha.toString().split(' ')[0]}.',
    );

    notifyListeners();
  }

  Future<void> suspenderEmpresa(String empresaId, {String motivo = ''}) async {
    final idx = _empresas.indexWhere((e) => e.id == empresaId);
    if (idx == -1) return;

    final e = _empresas[idx];
    _empresas[idx] = e.copyWith(estado: 'suspendido');
    await _guardarEmpresas();

    // Suspender y cerrar sesiones en MySQL inmediatamente
    await ApiService.manageTenant(
      tenantKey: resolverTenantKey(e),
      action: 'suspend',
      email: e.emailContacto,
    );

    await registrarLog(
      empresaId: e.id,
      empresaNombre: e.nombreComercial,
      accion: 'SUSPENDER_EMPRESA',
      descripcion: 'Empresa suspendida y sesiones activas cerradas en MySQL.${motivo.isNotEmpty ? ' Motivo: $motivo' : ''}',
    );

    notifyListeners();
  }

  Future<void> reactivarEmpresa(String empresaId) async {
    final idx = _empresas.indexWhere((e) => e.id == empresaId);
    if (idx == -1) return;

    final e = _empresas[idx];
    final nuevoEstado = e.esFree ? 'activo_free' : (e.esTrial ? 'trial_pro' : 'activo_pro');
    _empresas[idx] = e.copyWith(estado: nuevoEstado);
    await _guardarEmpresas();

    // Reactivar acceso en MySQL
    await ApiService.manageTenant(
      tenantKey: resolverTenantKey(e),
      action: 'reactivate',
      email: e.emailContacto,
    );

    await registrarLog(
      empresaId: e.id,
      empresaNombre: e.nombreComercial,
      accion: 'REACTIVAR_EMPRESA',
      descripcion: 'Empresa reactivada satisfactoriamente en estado $nuevoEstado en MySQL.',
    );

    notifyListeners();
  }

  Future<void> eliminarEmpresa(String empresaId, {bool softDelete = true}) async {
    final idx = _empresas.indexWhere((e) => e.id == empresaId);
    if (idx == -1) return;

    final e = _empresas[idx];
    if (softDelete) {
      _empresas[idx] = e.copyWith(
        estado: 'eliminado',
        eliminadoEn: DateTime.now(),
      );
      await _guardarEmpresas();

      // Bloquear acceso en MySQL inmediatamente
      await ApiService.manageTenant(
        tenantKey: resolverTenantKey(e),
        action: 'soft_delete',
        email: e.emailContacto,
      );

      await registrarLog(
        empresaId: e.id,
        empresaNombre: e.nombreComercial,
        accion: 'ENVIAR_PAPELERA',
        descripcion: 'Empresa enviada a la papelera (30 días) y acceso bloqueado inmediatamente en MySQL.',
      );
    } else {
      _empresas.removeAt(idx);
      await _guardarEmpresas();

      // Purgar definitivamente de MySQL
      await ApiService.manageTenant(
        tenantKey: resolverTenantKey(e),
        action: 'hard_delete',
        email: e.emailContacto,
      );

      await registrarLog(
        empresaId: e.id,
        empresaNombre: e.nombreComercial,
        accion: 'PURGA_PERMANENTE',
        descripcion: 'Empresa y todos sus datos purgados permanentemente de la base de datos.',
      );
    }

    notifyListeners();
  }

  Future<void> restaurarEmpresa(String empresaId) async {
    final idx = _empresas.indexWhere((e) => e.id == empresaId);
    if (idx == -1) return;

    final e = _empresas[idx];
    final nuevoEstado = e.esFree ? 'activo_free' : (e.esTrial ? 'trial_pro' : 'activo_pro');
    _empresas[idx] = e.copyWith(
      estado: nuevoEstado,
      eliminadoEn: null,
    );
    await _guardarEmpresas();

    // Reactivar acceso en MySQL
    await ApiService.manageTenant(
      tenantKey: resolverTenantKey(e),
      action: 'restore',
      email: e.emailContacto,
    );

    await registrarLog(
      empresaId: e.id,
      empresaNombre: e.nombreComercial,
      accion: 'RESTAURAR_EMPRESA',
      descripcion: 'Empresa restaurada de la papelera y acceso reactivado en MySQL.',
    );

    notifyListeners();
  }

  Future<void> registrarPago(PagoModel pago) async {
    _pagos.insert(0, pago);
    await _guardarPagos();

    // Actualizar fecha de vencimiento en la empresa
    final idx = _empresas.indexWhere((e) => e.id == pago.empresaId);
    if (idx != -1) {
      final e = _empresas[idx];
      _empresas[idx] = e.copyWith(
        fechaVencimiento: pago.fechaCoberturaHasta,
        estado: 'activo_pro',
      );
      await _guardarEmpresas();
    }

    await registrarLog(
      empresaId: pago.empresaId,
      empresaNombre: pago.empresaNombre,
      accion: 'REGISTRO_PAGO',
      descripcion: 'Pago de ${pago.moneda} ${pago.monto.toStringAsFixed(2)} registrado (${pago.mesesPagados} meses). Ref: ${pago.referenciaTransaccion}',
    );

    notifyListeners();
  }

  Future<void> guardarPlanesActualizados(List<PlanModel> planesActualizados) async {
    _planes = planesActualizados;
    await _guardarPlanes();

    await registrarLog(
      usuarioSuperadmin: 'SuperAdmin Novaled',
      accion: 'CONFIGURACION_PLANES',
      descripcion: 'Límites y precios de los planes actualizados.',
    );

    notifyListeners();
  }

  Future<void> registrarLog({
    String? empresaId,
    String? empresaNombre,
    String usuarioSuperadmin = 'SuperAdmin Novaled',
    required String accion,
    required String descripcion,
    Map<String, dynamic>? detalles,
  }) async {
    final log = LogAuditoriaModel(
      id: _uuid.v4(),
      empresaId: empresaId,
      empresaNombre: empresaNombre,
      usuarioSuperadmin: usuarioSuperadmin,
      accion: accion,
      descripcion: descripcion,
      detalles: detalles,
      fecha: DateTime.now(),
    );
    _logs.insert(0, log);
    await _guardarLogs();
  }

  // --- PERSISTENCIA LOCAL ---

  Future<void> _guardarEmpresas() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_empresas.map((e) => e.toMap()).toList());
    await prefs.setString('panel_empresas', data);
  }

  Future<void> _guardarPlanes() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_planes.map((p) => p.toMap()).toList());
    await prefs.setString('panel_planes', data);
  }

  Future<void> _guardarPagos() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_pagos.map((p) => p.toMap()).toList());
    await prefs.setString('panel_pagos', data);
  }

  Future<void> _guardarLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_logs.map((l) => l.toMap()).toList());
    await prefs.setString('panel_logs', data);
  }
}

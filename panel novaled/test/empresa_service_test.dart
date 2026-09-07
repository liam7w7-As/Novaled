import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:panel_novaled/services/empresa_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('EmpresaService inicializa con datos de demostración y cálculo de MRR', () async {
    final service = EmpresaService.instance;
    await service.inicializar();

    expect(service.empresas.isNotEmpty, true);
    expect(service.planes.length, 3);
    expect(service.totalEmpresasActivas, greaterThan(0));
    expect(service.ingresosRecurrentesMRR, greaterThan(0));
  });

  test('Crear empresa Free no tiene fecha de vencimiento', () async {
    final service = EmpresaService.instance;
    await service.inicializar();

    await service.crearEmpresa(
      nombreComercial: 'Empresa Test Free',
      emailContacto: 'testfree@novaled.bo',
      planId: 'free',
    );

    final creada = service.empresas.firstWhere((e) => e.nombreComercial == 'Empresa Test Free');
    expect(creada.esFree, true);
    expect(creada.fechaVencimiento, isNull);
    expect(creada.estado, 'activo_free');
  });

  test('Crear empresa PRO con Trial calcula fecha de vencimiento correcta', () async {
    final service = EmpresaService.instance;
    await service.inicializar();

    await service.crearEmpresa(
      nombreComercial: 'Empresa Test Trial',
      emailContacto: 'testtrial@novaled.bo',
      planId: 'pro_mensual',
      esTrial: true,
      diasTrial: 14,
    );

    final creada = service.empresas.firstWhere((e) => e.nombreComercial == 'Empresa Test Trial');
    expect(creada.esTrial, true);
    expect(creada.fechaVencimiento, isNotNull);
    expect(creada.diasRestantes, inInclusiveRange(13, 14));
  });

  test('Extender prórroga suma días al vencimiento', () async {
    final service = EmpresaService.instance;
    await service.inicializar();

    await service.crearEmpresa(
      nombreComercial: 'Empresa Prorroga',
      emailContacto: 'prorroga@novaled.bo',
      planId: 'pro_mensual',
      esTrial: true,
      diasTrial: 7,
    );

    final creada = service.empresas.firstWhere((e) => e.nombreComercial == 'Empresa Prorroga');
    final vencimientoInicial = creada.fechaVencimiento!;

    await service.extenderProrroga(creada.id, 15);
    final actualizada = service.getEmpresaById(creada.id)!;

    expect(actualizada.fechaVencimiento!.isAfter(vencimientoInicial), true);
  });

  test('Suspender y Reactivar empresa actualiza su estado y genera log de auditoría', () async {
    final service = EmpresaService.instance;
    await service.inicializar();

    await service.crearEmpresa(
      nombreComercial: 'Empresa Suspendible',
      emailContacto: 'susp@novaled.bo',
      planId: 'free',
    );

    final creada = service.empresas.firstWhere((e) => e.nombreComercial == 'Empresa Suspendible');
    await service.suspenderEmpresa(creada.id, motivo: 'Falta de verificación');

    var emp = service.getEmpresaById(creada.id)!;
    expect(emp.estaSuspendido, true);

    await service.reactivarEmpresa(creada.id);
    emp = service.getEmpresaById(creada.id)!;
    expect(emp.estaSuspendido, false);

    expect(service.logs.any((l) => l.accion == 'SUSPENDER_EMPRESA'), true);
    expect(service.logs.any((l) => l.accion == 'REACTIVAR_EMPRESA'), true);
  });
}

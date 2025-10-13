import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { QueryDocumentSnapshot } from "firebase-admin/firestore";

if (admin.apps.length === 0) {
  admin.initializeApp();
}
const db = admin.firestore();

type PagoDoc = {
  idMetodoPago: string;
  idAsignacion: string;
  montoTotal: number;
};

type MetodoPagoDoc = {
  codigo?: string; // ej. "DIRECTO_EFECTIVO", "APP_TARJETA"
};

type AsignacionDoc = {
  idConductorVehiculo?: string;
};

type ConductorVehiculoDoc = {
  idConductor?: string;
};

export const onCreatePagoGeneraComision = onDocumentCreated(
  "pagos/{pagoId}",
  async (event) => {
    const snap = event.data as QueryDocumentSnapshot;
    if (!snap) return;

    const pago = snap.data() as PagoDoc;
    if (!pago?.idMetodoPago || !pago?.idAsignacion) return;

    const metodoSnap = await db
      .collection("metodo_pago")
      .doc(pago.idMetodoPago)
      .get();
    const metodo = metodoSnap.data() as MetodoPagoDoc | undefined;
    const codigo = (metodo?.codigo ?? "").toUpperCase();

    // Solo generar comisión si es un pago DIRECTO_*
    if (!codigo.startsWith("DIRECTO_")) return;

    // asignación -> conductor_vehiculo -> conductor
    const asigSnap = await db
      .collection("asignaciones")
      .doc(pago.idAsignacion)
      .get();
    const asig = asigSnap.data() as AsignacionDoc | undefined;
    const idCV = asig?.idConductorVehiculo;
    if (!idCV) return;

    const cvSnap = await db.collection("conductor_vehiculo").doc(idCV).get();
    const cv = cvSnap.data() as ConductorVehiculoDoc | undefined;
    const idConductor = cv?.idConductor;
    if (!idConductor) return;

    const base = Number(pago.montoTotal) || 0;
    const porcentaje = 15.0; // regla actual
    const monto = Math.round(base * (porcentaje / 100) * 100) / 100; // 2 decimales

    await db.collection("comisiones").add({
      idAsignacion: pago.idAsignacion,
      idConductor,
      baseCalculo: base,
      porcentaje,
      monto,
      estado: "GENERADA",
      creadoEn: admin.firestore.FieldValue.serverTimestamp(),
    });
  },
);

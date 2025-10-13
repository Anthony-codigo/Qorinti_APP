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
  emitirComprobante?: boolean;
  tipoComprobanteCodigo?: string; // "BOLETA" | "FACTURA"
  idEmisorFiscal?: string;
  idEmpresaReceptora?: string; // para FACTURA
  idUsuarioReceptor?: string; // para BOLETA
  moneda?: string; // default "PEN"
};

type MetodoPagoDoc = {
  codigo?: string; // ej. "APP_TARJETA", "DIRECTO_EFECTIVO"
};

export const onCreatePago = onDocumentCreated(
  "pagos/{pagoId}",
  async (event) => {
    const snap = event.data as QueryDocumentSnapshot;
    if (!snap) return;

    const pago = snap.data() as PagoDoc;
    if (!pago || !pago.idMetodoPago) return;

    // Si no se pidió comprobante, no hacemos nada
    if (!pago.emitirComprobante) return;

    // Reglas: FACTURA solo con métodos APP_*
    const metodoRef = db.collection("metodo_pago").doc(pago.idMetodoPago);
    const metodoSnap = await metodoRef.get();
    const metodo = metodoSnap.data() as MetodoPagoDoc | undefined;
    const codigo = (metodo?.codigo ?? "").toUpperCase();

    const tipo = (pago.tipoComprobanteCodigo ?? "BOLETA").toUpperCase();
    if (tipo === "FACTURA" && !codigo.startsWith("APP_")) {
      await snap.ref.update({ inconsistencia: "FACTURA_requiere_APP" });
      return;
    }

    // Numeración simple (ejemplo)
    const serie = tipo === "FACTURA" ? "F001" : "B001";
    const numero = Date.now().toString();

    await db.collection("comprobantes").add({
      idPago: snap.id,
      tipoComprobante: tipo,
      idEmisorFiscal: pago.idEmisorFiscal ?? "QORINTI",
      idEmpresaReceptora:
        tipo === "FACTURA" ? (pago.idEmpresaReceptora ?? null) : null,
      idUsuarioReceptor:
        tipo === "BOLETA" ? (pago.idUsuarioReceptor ?? null) : null,
      serie,
      numero,
      total: pago.montoTotal,
      moneda: pago.moneda ?? "PEN",
      emitidoEn: admin.firestore.FieldValue.serverTimestamp(),
    });
  },
);

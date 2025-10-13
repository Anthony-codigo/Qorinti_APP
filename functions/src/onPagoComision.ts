import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { QueryDocumentSnapshot } from "firebase-admin/firestore";

if (admin.apps.length === 0) {
  admin.initializeApp();
}
const db = admin.firestore();

type PagoComisionDoc = {
  idComision: string;
  monto: number;
};

type ComisionDoc = {
  idConductor: string;
  monto: number;
  estado?: string; // GENERADA | PARCIAL | PAGADA
};

export const onPagoComision = onDocumentCreated(
  "pago_comision/{id}",
  async (event) => {
    const snap = event.data as QueryDocumentSnapshot;
    if (!snap) return;

    const pc = snap.data() as PagoComisionDoc;
    if (!pc?.idComision) return;

    const comiRef = db.collection("comisiones").doc(pc.idComision);
    const comiSnap = await comiRef.get();
    const comi = comiSnap.data() as ComisionDoc | undefined;
    if (!comi) return;

    // Recalcular estado de la comisión en base a pagos de esa comisión
    const pagosQ = await db
      .collection("pago_comision")
      .where("idComision", "==", pc.idComision)
      .get();
    const totalPagos = pagosQ.docs.reduce(
      (acc, d) => acc + Number((d.data().monto as number) || 0),
      0,
    );

    const estado =
      totalPagos >= (comi.monto || 0)
        ? "PAGADA"
        : totalPagos > 0
          ? "PARCIAL"
          : "GENERADA";

    await comiRef.update({ estado });

    // Actualizar estado de cuenta del conductor (suma de comisiones no pagadas)
    const pendQ = await db
      .collection("comisiones")
      .where("idConductor", "==", comi.idConductor)
      .get();
    const deuda = pendQ.docs
      .map((d) => d.data() as ComisionDoc)
      .filter((c) => (c.estado ?? "GENERADA") !== "PAGADA")
      .reduce((s, c) => s + Number(c.monto || 0), 0);

    const eccQ = await db
      .collection("estado_cuenta_conductor")
      .where("idConductor", "==", comi.idConductor)
      .limit(1)
      .get();

    const payload = {
      idConductor: comi.idConductor,
      saldo: deuda,
      actualizadoEn: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (eccQ.empty) {
      await db.collection("estado_cuenta_conductor").add(payload);
    } else {
      await eccQ.docs[0].ref.update(payload);
    }
  },
);

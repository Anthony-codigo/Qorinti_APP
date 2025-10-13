// functions/src/index.ts
import * as admin from "firebase-admin";
if (admin.apps.length === 0) {
  admin.initializeApp();
}

// Re-exporta TODAS las funciones
export * from "./onCreatePago";
export * from "./onCreatePagoComision";
export * from "./onPagoComision";

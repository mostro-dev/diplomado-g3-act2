import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  vus: 10, // 10 usuarios virtuales
  iterations: 1000, // Total de peticiones
  duration: "30s", // Tiempo total
};

// Índice global para iteraciones (variable compartida entre VUs)
let globalIndex = 0;

// Bloque para incrementar el índice global de forma segura
function getGlobalIndex() {
  return globalIndex++;
}

// Generar placa de vehículo
function generateVehiclePlate() {
  const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  const numbers = "0123456789";
  return `${letters.charAt(
    Math.floor(Math.random() * letters.length)
  )}${letters.charAt(
    Math.floor(Math.random() * letters.length)
  )}${letters.charAt(
    Math.floor(Math.random() * letters.length)
  )}-${numbers.charAt(
    Math.floor(Math.random() * numbers.length)
  )}${numbers.charAt(
    Math.floor(Math.random() * numbers.length)
  )}${numbers.charAt(Math.floor(Math.random() * numbers.length))}`;
}

// Generar coordenadas
function generateCoordinates() {
  return {
    latitude: (Math.random() * 180 - 90).toFixed(6),
    longitude: (Math.random() * 360 - 180).toFixed(6),
  };
}

// Generar tipo de mensaje usando índice global calculado
function generateType(globalIndex) {
  return globalIndex < 999 ? "Position" : "Emergency";
}

// Función principal
export default function () {
  // Cálculo del índice global
  const globalIndex = (__VU - 1) * (options.iterations / options.vus) + __ITER;

  let type = generateType(globalIndex);
  const payload = JSON.stringify({
    type: type,
    vehicle_plate: generateVehiclePlate(),
    coordinates: generateCoordinates(),
    status: "OK",
  });

  const headers = { "Content-Type": "application/json" };

  const res = http.post(
    "https://0rmjxymg93.execute-api.us-east-1.amazonaws.com/prod/event-notification",
    payload,
    { headers }
  );

  console.log(
    JSON.stringify({
      type: type,
      // timestamp: new Date().toISOString(),
      status: res.status,
      duration: res.timings.duration,
      globalIndex,
    })
  );

  if (res.status !== 200) {
    console.error(
      JSON.stringify({
        type: type,
        status: res.status,
        duration: res.timings.duration,
        globalIndex,
      })
    );
  }

  check(res, {
    "is status 200": (r) => r.status === 200,
  });

  sleep(0.1);
}

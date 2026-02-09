import createHttpError from "http-errors";

export type AppError = {
  statusCode: number;
  message: string;
  details?: unknown;
};

export function badRequest(message: string, details?: unknown) {
  return createHttpError(400, message, { details });
}

export function serviceUnavailable(message: string, details?: unknown) {
  return createHttpError(503, message, { details });
}

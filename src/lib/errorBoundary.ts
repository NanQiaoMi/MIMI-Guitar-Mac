/**
 * Unified Error Boundary and API Response Types
 */

export type ApiErrorCode =
  | 'NOT_FOUND'
  | 'UNAUTHORIZED'
  | 'FORBIDDEN'
  | 'VALIDATION_ERROR'
  | 'DATABASE_ERROR'
  | 'NETWORK_ERROR'
  | 'QUOTA_EXCEEDED'
  | 'INTERNAL_ERROR';

export interface ApiError {
  code: ApiErrorCode;
  message: string;
  recoverable: boolean;
  details?: Record<string, unknown>;
}

export type ApiResponse<T> =
  | { ok: true; data: T }
  | { ok: false; error: ApiError };

export function successResponse<T>(data: T): ApiResponse<T> {
  return { ok: true, data };
}

export function errorResponse(
  code: ApiErrorCode,
  message: string,
  recoverable = true,
  details?: Record<string, unknown>
): ApiResponse<never> {
  return {
    ok: false,
    error: { code, message, recoverable, details },
  };
}

export function isRecoverableError(error: ApiError): boolean {
  return error.recoverable;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** Returns true only for the explicit failure shape used by ApiResponse. */
export function isApiFailureResponse(value: unknown): boolean {
  return isRecord(value) && value.ok === false;
}

/** Reads both legacy string errors and the current structured API error. */
export function readApiErrorMessage(value: unknown, fallback: string): string {
  if (!isRecord(value)) return fallback;
  const error = value.error;
  const message = typeof error === 'string'
    ? error
    : isRecord(error) && typeof error.message === 'string'
      ? error.message
      : '';
  return message.trim() || fallback;
}

const PRISMA_ERROR_NAMES = new Set([
  'PrismaClientKnownRequestError',
  'PrismaClientUnknownRequestError',
  'PrismaClientInitializationError',
  'PrismaClientRustPanicError',
  'PrismaClientValidationError',
]);

const NETWORK_ERROR_CODES = new Set([
  'ECONNABORTED',
  'ECONNREFUSED',
  'ECONNRESET',
  'EHOSTUNREACH',
  'EAI_AGAIN',
  'ENETUNREACH',
  'ENOTFOUND',
  'EPIPE',
  'ETIMEDOUT',
]);

export function isDatabaseError(error: unknown): boolean {
  if (!isRecord(error)) return false;
  if (typeof error.name === 'string' && PRISMA_ERROR_NAMES.has(error.name)) return true;
  if (typeof error.code !== 'string') return false;
  return /^P\d{4}$/.test(error.code) || NETWORK_ERROR_CODES.has(error.code);
}

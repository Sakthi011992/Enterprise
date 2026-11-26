import { HttpException } from '@nestjs/common';

const ERROR_NAMES: Record<number, string> = {
  400: 'Bad Request',
  401: 'Unauthorized',
  403: 'Forbidden',
  404: 'Not Found',
  409: 'Conflict',
  410: 'Gone',
  423: 'Locked',
  429: 'Too Many Requests',
  501: 'Not Implemented',
  503: 'Service Unavailable',
};

/**
 * Builds an HTTP error that carries a stable machine-readable `code` and
 * optional `details`. AllExceptionsFilter passes both through to the client.
 */
export function apiError(
  status: number,
  code: string,
  message: string,
  details?: Record<string, unknown>,
): HttpException {
  return new HttpException(
    {
      statusCode: status,
      message,
      error: ERROR_NAMES[status] ?? 'Error',
      code,
      ...(details ? { details } : {}),
    },
    status,
  );
}

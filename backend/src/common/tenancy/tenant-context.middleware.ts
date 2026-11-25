import { Injectable, NestMiddleware } from '@nestjs/common';
import { NextFunction, Request, Response } from 'express';
import { TenantContext } from './tenant-context';

/** Opens an empty tenant store for every request. JwtStrategy fills it in later. */
@Injectable()
export class TenantContextMiddleware implements NestMiddleware {
  use(_req: Request, _res: Response, next: NextFunction): void {
    TenantContext.run({}, () => next());
  }
}

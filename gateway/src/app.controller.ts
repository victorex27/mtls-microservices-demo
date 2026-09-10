import { Controller, Get, Param, Req } from '@nestjs/common';
import { Request } from 'express';
import { firstValueFrom } from 'rxjs';
import { UsersClientService } from './users.client';

@Controller()
export class AppController {
  constructor(private readonly usersClient: UsersClientService) {}

  @Get('healthz')
  health() {
    return { status: 'ok', service: 'gateway' };
  }

  /**
   * Shows the caller's own client certificate, as validated by Node's TLS
   * layer during the mTLS handshake. Useful to prove mTLS is actually being
   * enforced on the way IN to the gateway (see docs/TESTING_MTLS.md).
   */
  @Get('whoami')
  whoami(@Req() req: Request) {
    const socket = req.socket as any;
    const cert = socket.getPeerCertificate ? socket.getPeerCertificate() : null;
    return {
      authorized: socket.authorized ?? null,
      peerCertificateSubject: cert?.subject ?? null,
      peerCertificateIssuer: cert?.issuer ?? null,
    };
  }

  /**
   * gateway --(mTLS gRPC)--> users-service --(mTLS gRPC)--> orders-service
   */
  @Get('users/:id')
  async getUser(@Param('id') id: string) {
    const result = await firstValueFrom(this.usersClient.getUser(id));
    return result;
  }
}

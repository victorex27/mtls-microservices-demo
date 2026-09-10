import { Inject, Injectable, OnModuleInit } from '@nestjs/common';
import { ClientGrpc, ClientsModule, Transport } from '@nestjs/microservices';
import { credentials } from '@grpc/grpc-js';
import * as path from 'path';
import { Observable } from 'rxjs';
import { loadMtlsPaths, readMtlsFiles } from './mtls.util';

export interface GetUserResponse {
  id: string;
  name: string;
  email: string;
  orders: string[];
  servedBy: string;
}

interface UsersServiceGrpc {
  getUser(data: { id: string }): Observable<GetUserResponse>;
}

/**
 * Builds the mTLS gRPC client options for talking to users-service.
 * The gateway presents its OWN cert (proving "I am api-gateway") and
 * validates the server cert users-service presents against the shared CA.
 */
export function usersServiceClientOptions() {
  const paths = loadMtlsPaths();
  const { ca, cert, key } = readMtlsFiles(paths);

  return {
    transport: Transport.GRPC as const,
    options: {
      package: 'users',
      protoPath: path.join(__dirname, '../proto/users.proto'),
      url: process.env.USERS_SERVICE_URL || 'localhost:50051',
      credentials: credentials.createSsl(ca, key, cert),
      channelOptions: {
        // Must match the SAN on the users-service certificate exactly.
        'grpc.ssl_target_name_override':
          process.env.USERS_SERVICE_TLS_SERVER_NAME || 'users-service',
        'grpc.default_authority':
          process.env.USERS_SERVICE_TLS_SERVER_NAME || 'users-service',
      },
    },
  };
}

export const UsersClientModule = ClientsModule.registerAsync([
  {
    name: 'USERS_SERVICE',
    useFactory: () => usersServiceClientOptions(),
  },
]);

@Injectable()
export class UsersClientService implements OnModuleInit {
  private usersService: UsersServiceGrpc;

  constructor(@Inject('USERS_SERVICE') private readonly client: ClientGrpc) {}

  onModuleInit() {
    this.usersService = this.client.getService<UsersServiceGrpc>('UsersService');
  }

  getUser(id: string) {
    return this.usersService.getUser({ id });
  }
}

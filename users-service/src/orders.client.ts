import { Inject, Injectable, OnModuleInit } from '@nestjs/common';
import { ClientGrpc, ClientsModule, Transport } from '@nestjs/microservices';
import { credentials } from '@grpc/grpc-js';
import * as path from 'path';
import { Observable } from 'rxjs';
import { loadMtlsPaths, readMtlsFiles } from './mtls.util';

export interface GetOrdersResponse {
  userId: string;
  orders: string[];
  servedBy: string;
}

interface OrdersServiceGrpc {
  getOrdersForUser(data: { userId: string }): Observable<GetOrdersResponse>;
}

/**
 * users-service acting as a gRPC CLIENT to orders-service. This is the
 * "some gRPC services talk to other gRPC services" leg of the architecture:
 * users-service presents its own cert (CN=users-service) to orders-service,
 * which validates it against the shared CA just like the gateway did to it.
 */
export function ordersServiceClientOptions() {
  const paths = loadMtlsPaths();
  const { ca, cert, key } = readMtlsFiles(paths);

  return {
    transport: Transport.GRPC as const,
    options: {
      package: 'orders',
      protoPath: path.join(__dirname, '../proto/orders.proto'),
      url: process.env.ORDERS_SERVICE_URL || 'localhost:50052',
      credentials: credentials.createSsl(ca, key, cert),
      channelOptions: {
        'grpc.ssl_target_name_override':
          process.env.ORDERS_SERVICE_TLS_SERVER_NAME || 'orders-service',
        'grpc.default_authority':
          process.env.ORDERS_SERVICE_TLS_SERVER_NAME || 'orders-service',
      },
    },
  };
}

export const OrdersClientModule = ClientsModule.registerAsync([
  {
    name: 'ORDERS_SERVICE',
    useFactory: () => ordersServiceClientOptions(),
  },
]);

@Injectable()
export class OrdersClientService implements OnModuleInit {
  private ordersService: OrdersServiceGrpc;

  constructor(@Inject('ORDERS_SERVICE') private readonly client: ClientGrpc) {}

  onModuleInit() {
    this.ordersService = this.client.getService<OrdersServiceGrpc>('OrdersService');
  }

  getOrdersForUser(userId: string) {
    return this.ordersService.getOrdersForUser({ userId });
  }
}

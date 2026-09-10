import { Controller } from '@nestjs/common';
import { GrpcMethod } from '@nestjs/microservices';
import { firstValueFrom } from 'rxjs';
import * as os from 'os';
import { OrdersClientService } from './orders.client';

const MOCK_USERS: Record<string, { name: string; email: string }> = {
  '1': { name: 'Ada Lovelace', email: 'ada@example.com' },
  '2': { name: 'Grace Hopper', email: 'grace@example.com' },
};

@Controller()
export class AppController {
  constructor(private readonly ordersClient: OrdersClientService) {}

  @GrpcMethod('UsersService', 'GetUser')
  async getUser(data: { id: string }) {
    const user = MOCK_USERS[data.id] ?? {
      name: `Unknown User ${data.id}`,
      email: 'unknown@example.com',
    };

    // Chained internal gRPC call, itself over mTLS.
    const ordersResult = await firstValueFrom(
      this.ordersClient.getOrdersForUser(data.id),
    );

    return {
      id: data.id,
      name: user.name,
      email: user.email,
      orders: ordersResult.orders,
      servedBy: `users-service@${os.hostname()} (orders served by ${ordersResult.servedBy})`,
    };
  }
}

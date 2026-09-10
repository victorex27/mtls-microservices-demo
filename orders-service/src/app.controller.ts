import { Controller } from '@nestjs/common';
import { GrpcMethod } from '@nestjs/microservices';
import * as os from 'os';

const MOCK_ORDERS: Record<string, string[]> = {
  '1': ['order-1001', 'order-1002'],
  '2': ['order-2001'],
};

@Controller()
export class AppController {
  @GrpcMethod('OrdersService', 'GetOrdersForUser')
  getOrdersForUser(data: { userId: string }) {
    return {
      userId: data.userId,
      orders: MOCK_ORDERS[data.userId] ?? [],
      servedBy: `orders-service@${os.hostname()}`,
    };
  }
}

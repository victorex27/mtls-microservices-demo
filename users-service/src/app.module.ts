import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { OrdersClientModule, OrdersClientService } from './orders.client';

@Module({
  imports: [OrdersClientModule],
  controllers: [AppController],
  providers: [OrdersClientService],
})
export class AppModule {}

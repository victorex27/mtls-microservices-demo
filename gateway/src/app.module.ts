import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { UsersClientModule, UsersClientService } from './users.client';

@Module({
  imports: [UsersClientModule],
  controllers: [AppController],
  providers: [UsersClientService],
})
export class AppModule {}

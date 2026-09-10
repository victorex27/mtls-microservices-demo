import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { MicroserviceOptions, Transport } from '@nestjs/microservices';
import { ServerCredentials } from '@grpc/grpc-js';
import * as path from 'path';
import { AppModule } from './app.module';
import { loadMtlsPaths, readMtlsFiles } from './mtls.util';
import { watchCertsForRotation } from './cert-watcher';

async function bootstrap() {
  const paths = loadMtlsPaths();
  const { ca, cert, key } = readMtlsFiles(paths);

  // checkClientCertificate=true is what makes this mTLS instead of plain
  // server-side TLS: the server will refuse the handshake unless the client
  // presents a cert signed by our CA.
  const grpcCredentials = ServerCredentials.createSsl(
    ca,
    [{ cert_chain: cert, private_key: key }],
    true,
  );

  const port = process.env.USERS_GRPC_PORT || '50051';

  const app = await NestFactory.createMicroservice<MicroserviceOptions>(AppModule, {
    transport: Transport.GRPC,
    options: {
      package: 'users',
      protoPath: path.join(__dirname, '../proto/users.proto'),
      url: `0.0.0.0:${port}`,
      credentials: grpcCredentials,
    },
  });

  await app.listen();
  // eslint-disable-next-line no-console
  console.log(`[users-service] gRPC (mTLS) listening on 0.0.0.0:${port}`);

  if (process.env.WATCH_CERTS_FOR_ROTATION !== 'false') {
    watchCertsForRotation(paths, (msg) => console.log(`[users-service] ${msg}`));
  }
}

bootstrap().catch((err) => {
  // eslint-disable-next-line no-console
  console.error('[users-service] fatal bootstrap error', err);
  process.exit(1);
});

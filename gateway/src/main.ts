import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module';
import { loadMtlsPaths, readMtlsFiles } from './mtls.util';
import { watchCertsForRotation } from './cert-watcher';

async function bootstrap() {
  const paths = loadMtlsPaths();
  const { ca, cert, key } = readMtlsFiles(paths);

  // requestCert + rejectUnauthorized enforce mTLS on every inbound HTTPS
  // connection: no client cert (or one not signed by our CA) -> handshake
  // fails before any NestJS route code ever runs.
  const httpsOptions = {
    key,
    cert,
    ca,
    requestCert: true,
    rejectUnauthorized: true,
  };

  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    httpsOptions,
  });

  const port = parseInt(process.env.GATEWAY_PORT || '3000', 10);
  await app.listen(port, '0.0.0.0');
  // eslint-disable-next-line no-console
  console.log(`[gateway] HTTPS (mTLS) listening on 0.0.0.0:${port}`);

  if (process.env.WATCH_CERTS_FOR_ROTATION !== 'false') {
    watchCertsForRotation(paths, (msg) => console.log(`[gateway] ${msg}`));
  }
}

bootstrap().catch((err) => {
  // eslint-disable-next-line no-console
  console.error('[gateway] fatal bootstrap error', err);
  process.exit(1);
});

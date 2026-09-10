import * as fs from 'fs';
import { MtlsPaths } from './mtls.util';

/**
 * Watches the cert/key files on disk. When Vault Agent (or a manual
 * rotation script) rewrites them in place, this exits the process with a
 * distinguished code (99) that the container's entrypoint.sh interprets as
 * "restart me" rather than "crash". On restart, main.ts re-reads the fresh
 * PEM files from disk.
 *
 * This is a deliberately simple rotation strategy - full hot-reload of a
 * live TLS/gRPC server's credentials without dropping connections is
 * possible but substantially more code (see docs/VAULT.md "Future work").
 * Restart-on-rotation is safe here because dokku/docker restart the
 * container in well under a second and the two other services will simply
 * retry their gRPC calls (see the client retry note in docs/VAULT.md).
 */
export function watchCertsForRotation(paths: MtlsPaths, logger: (msg: string) => void) {
  const files = [paths.caPath, paths.certPath, paths.keyPath];
  let debounce: NodeJS.Timeout | null = null;

  for (const file of files) {
    try {
      fs.watch(file, { persistent: false }, () => {
        if (debounce) clearTimeout(debounce);
        // Debounce because Vault Agent's template renderer can fire
        // multiple fs events for a single logical write.
        debounce = setTimeout(() => {
          logger(`detected change in ${file}, restarting to pick up rotated cert`);
          process.exit(99);
        }, 2000);
      });
    } catch (err) {
      logger(`warning: could not watch ${file} for rotation: ${(err as Error).message}`);
    }
  }
}

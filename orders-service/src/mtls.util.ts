import * as fs from 'fs';

export interface MtlsPaths {
  caPath: string;
  certPath: string;
  keyPath: string;
}

/**
 * Reads TLS_CA_PATH / TLS_CERT_PATH / TLS_KEY_PATH from the environment.
 *
 * These paths are deliberately the ONLY thing this app knows about certs.
 * Whether the files at those paths were written by ./scripts/gen-local-certs.sh
 * (localhost dev) or by a Vault Agent template renderer (deployed / vault-dev),
 * this app doesn't care - it just reads whatever PEM files are currently on disk
 * at boot. See docs/VAULT.md for how rotation triggers a restart so the new
 * files get picked up.
 */
export function loadMtlsPaths(): MtlsPaths {
  const caPath = process.env.TLS_CA_PATH;
  const certPath = process.env.TLS_CERT_PATH;
  const keyPath = process.env.TLS_KEY_PATH;

  if (!caPath || !certPath || !keyPath) {
    throw new Error(
      'Missing required env vars: TLS_CA_PATH, TLS_CERT_PATH, TLS_KEY_PATH. ' +
        'See .env.example / docs/LOCAL_TESTING.md',
    );
  }
  return { caPath, certPath, keyPath };
}

export function readMtlsFiles(paths: MtlsPaths) {
  return {
    ca: fs.readFileSync(paths.caPath),
    cert: fs.readFileSync(paths.certPath),
    key: fs.readFileSync(paths.keyPath),
  };
}

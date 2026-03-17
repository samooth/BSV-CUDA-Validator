export interface SignatureTask {
    hash: Buffer;      // 32 bytes
    sig: Buffer;       // Up to 72 bytes (DER)
    pubKey: Buffer;    // 65 bytes (uncompressed)
}

export function verifySignatures(tasks: SignatureTask[], callback: (err: Error | null, results: boolean[]) => void): void;
export function computeMerkleRoot(txHashes: Buffer[], callback: (err: Error | null, root: Buffer) => void): void;
export function verifySignaturesSync(tasks: SignatureTask[]): boolean[];
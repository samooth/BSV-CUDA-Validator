export interface SignatureTask {
    hash: Buffer | string;
    sig: Buffer | string;
    pubKey: Buffer | string;
}

export function verifySignatures(
    tasks: SignatureTask[],
    callback: (err: Error | null, results: boolean[]) => void
): void;

export function verifySignaturesSync(tasks: SignatureTask[]): boolean[];

export function computeMerkleRoot(
    txHashes: (Buffer | string)[],
    callback: (err: Error | null, root: Buffer) => void
): void;

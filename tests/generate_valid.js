const secp256k1 = require('secp256k1');
const crypto = require('crypto');

// 1. Generate a known keypair
const privKey = Buffer.from("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "hex");
const pubKey = secp256k1.publicKeyCreate(privKey, false); // Uncompressed 65 bytes

// 2. Message hash
const hash = crypto.createHash('sha256').update('BSV GPU TEST').digest();

// 3. Sign
const sigObj = secp256k1.ecdsaSign(hash, privKey);
const derSig = secp256k1.signatureExport(sigObj.signature);

console.log('--- TEST DATA ---');
console.log('Hash:', hash.toString('hex'));
console.log('Sig:', Buffer.from(derSig).toString('hex'));
console.log('PubKey:', Buffer.from(pubKey).toString('hex'));

// 4. Local Verify
const isValid = secp256k1.ecdsaVerify(sigObj.signature, hash, pubKey);
console.log('Local Verify:', isValid);

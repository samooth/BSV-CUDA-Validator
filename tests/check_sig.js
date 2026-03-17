const secp256k1 = require('secp256k1');

const hash = Buffer.from("f68255748d703b75d3495f4d29c62c1cf687e998301e7c1639245ee24959a13b", "hex");
const sig = Buffer.from("30440220734a61fe19960e730dc6d131656b6a61154e50f286ce8f7f93d76a9f89d2e971022031892b4cebebbe58fccad4235a242f024371578c2689ca192268754dc86c1cba41", "hex");
const pubKey = Buffer.from("0422cfa3253e2706e5a7d69785259d098c998e20d185ee515a2b9ad3177bca5b0f2ed62b1464b73b5df599f6674d896172960655ed510619a6d95f87b36f7537b983", "hex");

try {
    const isValid = secp256k1.ecdsaVerify(sig, hash, pubKey);
    console.log("Is Valid (CPU):", isValid);
} catch (e) {
    console.log("Direct verify failed:", e.message);
    try {
        const sigObj = secp256k1.signatureImport(sig);
        const isValidImport = secp256k1.ecdsaVerify(sigObj, hash, pubKey);
        console.log("Is Valid (with Import):", isValidImport);
    } catch (e2) {
        console.error("Import verify failed:", e2.message);
    }
}

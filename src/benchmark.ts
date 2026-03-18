import 'dotenv/config';

async function runBenchmark() {
    // TODO: Pon aquí un SIGHASH, Sig y PubKey REALES de una tx tuya para ver los "true"
    const task = {
        hash: "3d2117bc943ba3863e3385af09536b32c5103b20f472e7f93ac75150c0e1c8fb",
        sig: "3045022100d5404371bb627e481dd118bb2ff0982ef2330a122b639f0c4cd3287071efea90022035aa1b9a075651a4cc6fe4b8fb88bd725310bc575d171a6f9d37ba9e193c7b7a",
        pubKey: "04a34b99f22c790c4e36b2b3c2c35a36db06226e41c692fc82b8b56ac1c540c5bd5b8dec5235a0fa8722476c7709c02559e3aa73aa03918ba2d492eea75abea235"
    };

    // Vamos a enviarle 50,000 firmas de golpe a la GPU
    const BATCH_SIZE = 50000;
    const tasks = Array(BATCH_SIZE).fill(task);

    console.log(`🚀 Enviando batch de ${BATCH_SIZE} firmas a la GPU...`);
    const start = Date.now();

    try {
        const response = await fetch('http://localhost:8080/verify/signatures', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${process.env.GPU_TOKEN}`
            },
            body: JSON.stringify({ tasks })
        });

        const data = await response.json() as any;
        const end = Date.now();
        const elapsed = end - start;
        
        console.log(`✅ Batch completado en ${data.batchTimeMs} ms (tiempo de red/JSON: ${elapsed} ms)`);
        console.log(`⚡ Rendimiento puro de la GPU: ${Math.round(BATCH_SIZE / (data.batchTimeMs / 1000))} firmas/segundo`);
        console.log(`⚡ Rendimiento total (incluyendo HTTP/Node): ${Math.round(BATCH_SIZE / (elapsed / 1000))} firmas/segundo`);
        
    } catch (e) {
        console.error("Error en el benchmark:", e);
    }
}

runBenchmark();
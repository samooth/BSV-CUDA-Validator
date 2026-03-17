#include <nan.h>
#include <cstdint>
#include <cstring>
#include <vector>
#include <string>

// C++ struct matching CUDA struct exactly (with padding/alignment)
#pragma pack(push, 1)
typedef struct {
    uint8_t hash[32];
    uint8_t sig[72];
    uint8_t pubKey[65];
    uint16_t sigLen;
    uint16_t pubKeyLen;
} SignatureTask;
#pragma pack(pop)

// CUDA function declarations
extern "C" int cudaVerifyBatch(const SignatureTask* tasks, int numTasks, uint8_t* results);
extern "C" int cudaMerkleRoot(const uint8_t* txHashes, int numTx, uint8_t* root);

using namespace v8;

// Helper to decode hex string to buffer
bool hexToBuf(Local<Value> val, uint8_t* dst, size_t maxLen, uint16_t* outLen = nullptr) {
    if (val.IsEmpty() || val->IsNull() || val->IsUndefined()) return false;
    
    if (val->IsObject() && node::Buffer::HasInstance(val)) {
        size_t len = node::Buffer::Length(val);
        size_t copyLen = len < maxLen ? len : maxLen;
        memcpy(dst, node::Buffer::Data(val), copyLen);
        if (outLen) *outLen = (uint16_t)copyLen;
        return true;
    } else if (val->IsString()) {
        Nan::Utf8String hexStr(val);
        std::string s(*hexStr);
        if (s.length() % 2 != 0) return false;
        size_t len = s.length() / 2;
        size_t copyLen = len < maxLen ? len : maxLen;
        for (size_t i = 0; i < copyLen; i++) {
            std::string byteString = s.substr(i * 2, 2);
            dst[i] = (uint8_t)strtol(byteString.c_str(), NULL, 16);
        }
        if (outLen) *outLen = (uint16_t)copyLen;
        return true;
    }
    return false;
}

// ============================================================================
// Async Worker for Signature Verification
// ============================================================================

class VerifyWorker : public Nan::AsyncWorker {
public:
    VerifyWorker(Nan::Callback *callback, Local<Array> tasks)
        : AsyncWorker(callback), numTasks(0) {
        
        numTasks = tasks->Length();
        if (numTasks > 0) {
            h_tasks.resize(numTasks);
            memset(h_tasks.data(), 0, numTasks * sizeof(SignatureTask));
            
            for (int i = 0; i < numTasks; i++) {
                Nan::MaybeLocal<Value> maybeTask = Nan::Get(tasks, i);
                if (maybeTask.IsEmpty()) continue;
                
                Local<Value> taskVal = maybeTask.ToLocalChecked();
                if (!taskVal->IsObject()) continue;
                Local<Object> task = taskVal->ToObject(Nan::GetCurrentContext()).ToLocalChecked();
                
                Local<Value> hashVal = Nan::Get(task, Nan::New("hash").ToLocalChecked()).FromMaybe(Local<Value>());
                hexToBuf(hashVal, h_tasks[i].hash, 32);
                
                Local<Value> sigVal = Nan::Get(task, Nan::New("sig").ToLocalChecked()).FromMaybe(Local<Value>());
                hexToBuf(sigVal, h_tasks[i].sig, 72, &h_tasks[i].sigLen);
                
                Local<Value> pubVal = Nan::Get(task, Nan::New("pubKey").ToLocalChecked()).FromMaybe(Local<Value>());
                hexToBuf(pubVal, h_tasks[i].pubKey, 65, &h_tasks[i].pubKeyLen);
            }
        }
    }
    
    void Execute() {
        if (numTasks > 0) {
            h_results.resize(numTasks);
            int ret = cudaVerifyBatch(h_tasks.data(), numTasks, h_results.data());
            if (ret != 0) {
                SetErrorMessage("CUDA verification failed");
            }
        }
    }
    
    void HandleOKCallback() {
        Nan::HandleScope scope;
        Local<Array> results = Nan::New<Array>(numTasks);
        for (int i = 0; i < numTasks; i++) {
            bool success = (i < (int)h_results.size()) ? (h_results[i] == 1) : false;
            Nan::Set(results, i, Nan::New<Boolean>(success));
        }
        Local<Value> argv[] = { Nan::Null(), results };
        callback->Call(2, argv, async_resource);
    }
    
private:
    std::vector<SignatureTask> h_tasks;
    std::vector<uint8_t> h_results;
    int numTasks;
};

// ============================================================================
// Async Worker for Merkle Root
// ============================================================================

class MerkleWorker : public Nan::AsyncWorker {
public:
    MerkleWorker(Nan::Callback *callback, Local<Array> txHashes)
        : AsyncWorker(callback), numTx(0) {
        
        numTx = txHashes->Length();
        if (numTx > 0) {
            h_hashes.resize(numTx * 32, 0);
            for (int i = 0; i < numTx; i++) {
                Nan::MaybeLocal<Value> maybeHash = Nan::Get(txHashes, i);
                if (maybeHash.IsEmpty()) continue;
                hexToBuf(maybeHash.ToLocalChecked(), h_hashes.data() + i * 32, 32);
            }
        }
        memset(h_root, 0, 32);
    }
    
    void Execute() {
        if (numTx > 0) {
            int ret = cudaMerkleRoot(h_hashes.data(), numTx, h_root);
            if (ret != 0) {
                SetErrorMessage("CUDA Merkle computation failed");
            }
        }
    }
    
    void HandleOKCallback() {
        Nan::HandleScope scope;
        Local<Object> rootBuffer = Nan::CopyBuffer((char*)h_root, 32).ToLocalChecked();
        Local<Value> argv[] = { Nan::Null(), rootBuffer };
        callback->Call(2, argv, async_resource);
    }
    
private:
    std::vector<uint8_t> h_hashes;
    uint8_t h_root[32];
    int numTx;
};

// ============================================================================
// NAN Method Exports
// ============================================================================

NAN_METHOD(VerifySignatures) {
    if (info.Length() < 2 || !info[0]->IsArray() || !info[1]->IsFunction()) {
        Nan::ThrowTypeError("Expected (tasks: Object[], callback: Function)");
        return;
    }
    Local<Array> tasks = info[0].As<Array>();
    Local<Function> cb = info[1].As<Function>();
    Nan::Callback *callback = new Nan::Callback(cb);
    Nan::AsyncQueueWorker(new VerifyWorker(callback, tasks));
}

NAN_METHOD(ComputeMerkleRoot) {
    if (info.Length() < 2 || !info[0]->IsArray() || !info[1]->IsFunction()) {
        Nan::ThrowTypeError("Expected (txHashes: (Buffer|String)[], callback: Function)");
        return;
    }
    Local<Array> hashes = info[0].As<Array>();
    Local<Function> cb = info[1].As<Function>();
    Nan::Callback *callback = new Nan::Callback(cb);
    Nan::AsyncQueueWorker(new MerkleWorker(callback, hashes));
}

NAN_METHOD(VerifySignaturesSync) {
    if (info.Length() < 1 || !info[0]->IsArray()) {
        Nan::ThrowTypeError("Expected (tasks: Object[])");
        return;
    }
    
    Local<Array> tasks = info[0].As<Array>();
    int numTasks = tasks->Length();
    if (numTasks <= 0) {
        info.GetReturnValue().Set(Nan::New<Array>(0));
        return;
    }

    std::vector<SignatureTask> h_tasks(numTasks);
    memset(h_tasks.data(), 0, numTasks * sizeof(SignatureTask));
    
    for (int i = 0; i < numTasks; i++) {
        Nan::MaybeLocal<Value> maybeTask = Nan::Get(tasks, i);
        if (maybeTask.IsEmpty()) continue;
        Local<Value> taskVal = maybeTask.ToLocalChecked();
        if (!taskVal->IsObject()) continue;
        Local<Object> task = taskVal->ToObject(Nan::GetCurrentContext()).ToLocalChecked();
        
        hexToBuf(Nan::Get(task, Nan::New("hash").ToLocalChecked()).FromMaybe(Local<Value>()), h_tasks[i].hash, 32);
        hexToBuf(Nan::Get(task, Nan::New("sig").ToLocalChecked()).FromMaybe(Local<Value>()), h_tasks[i].sig, 72, &h_tasks[i].sigLen);
        hexToBuf(Nan::Get(task, Nan::New("pubKey").ToLocalChecked()).FromMaybe(Local<Value>()), h_tasks[i].pubKey, 65, &h_tasks[i].pubKeyLen);
    }
    
    std::vector<uint8_t> h_results(numTasks, 0);
    int ret = cudaVerifyBatch(h_tasks.data(), numTasks, h_results.data());
    
    Local<Array> results = Nan::New<Array>(numTasks);
    if (ret == 0) {
        for (int i = 0; i < numTasks; i++) {
            Nan::Set(results, i, Nan::New<Boolean>(h_results[i] == 1));
        }
    }
    
    info.GetReturnValue().Set(results);
}

NAN_MODULE_INIT(Init) {
    Nan::Set(target, Nan::New("verifySignatures").ToLocalChecked(),
        Nan::GetFunction(Nan::New<FunctionTemplate>(VerifySignatures)).ToLocalChecked());
    Nan::Set(target, Nan::New("computeMerkleRoot").ToLocalChecked(),
        Nan::GetFunction(Nan::New<FunctionTemplate>(ComputeMerkleRoot)).ToLocalChecked());
    Nan::Set(target, Nan::New("verifySignaturesSync").ToLocalChecked(),
        Nan::GetFunction(Nan::New<FunctionTemplate>(VerifySignaturesSync)).ToLocalChecked());
}

NODE_MODULE(bsv_cuda, Init)

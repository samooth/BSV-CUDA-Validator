#include <nan.h>
#include <cstdint>
#include <cstring>

// CUDA function declarations (from .cu files)
extern "C" int cudaVerifyBatch(const void* tasks, int numTasks, uint8_t** results);
extern "C" int cudaMerkleRoot(const uint8_t* txHashes, int numTx, uint8_t* root);

// C++ struct matching CUDA struct exactly
typedef struct {
    uint8_t hash[32];
    uint8_t sig[72];
    uint8_t pubKey[65];
    uint16_t sigLen;
} SignatureTask;

using namespace v8;

// ============================================================================
// Async Worker for Signature Verification
// ============================================================================

class VerifyWorker : public Nan::AsyncWorker {
public:
    VerifyWorker(Nan::Callback *callback, Local<Array> tasks)
        : AsyncWorker(callback), h_tasks(nullptr), h_results(nullptr), numTasks(0) {
        
        numTasks = tasks->Length();
        h_tasks = new SignatureTask[numTasks];
        
        for (int i = 0; i < numTasks; i++) {
            Nan::MaybeLocal<Value> maybeTask = Nan::Get(tasks, i);
            if (maybeTask.IsEmpty()) continue;
            
            Local<Object> task = maybeTask.ToLocalChecked()->ToObject(Nan::GetCurrentContext()).ToLocalChecked();
            
            // Extract hash (Buffer)
            Local<Value> hashVal = Nan::Get(task, Nan::New("hash").ToLocalChecked()).ToLocalChecked();
            if (hashVal->IsObject() && node::Buffer::HasInstance(hashVal)) {
                char* data = node::Buffer::Data(hashVal);
                size_t len = node::Buffer::Length(hashVal);
                memcpy(h_tasks[i].hash, data, len < 32 ? len : 32);
            }
            
            // Extract sig (Buffer)
            Local<Value> sigVal = Nan::Get(task, Nan::New("sig").ToLocalChecked()).ToLocalChecked();
            if (sigVal->IsObject() && node::Buffer::HasInstance(sigVal)) {
                char* data = node::Buffer::Data(sigVal);
                size_t len = node::Buffer::Length(sigVal);
                h_tasks[i].sigLen = len < 72 ? len : 72;
                memcpy(h_tasks[i].sig, data, h_tasks[i].sigLen);
            }
            
            // Extract pubKey (Buffer)
            Local<Value> pubVal = Nan::Get(task, Nan::New("pubKey").ToLocalChecked()).ToLocalChecked();
            if (pubVal->IsObject() && node::Buffer::HasInstance(pubVal)) {
                char* data = node::Buffer::Data(pubVal);
                size_t len = node::Buffer::Length(pubVal);
                memcpy(h_tasks[i].pubKey, data, len < 65 ? len : 65);
            }
        }
    }
    
    ~VerifyWorker() {
        if (h_tasks) delete[] h_tasks;
        if (h_results) free(h_results);
    }
    
    void Execute() {
        int ret = cudaVerifyBatch(h_tasks, numTasks, &h_results);
        if (ret != 0) {
            SetErrorMessage("CUDA verification failed");
        }
    }
    
    void HandleOKCallback() {
        Nan::HandleScope scope;
        
        Local<Array> results = Nan::New<Array>(numTasks);
        for (int i = 0; i < numTasks; i++) {
            Nan::Set(results, i, Nan::New<Boolean>(h_results[i] == 1));
        }
        
        Local<Value> argv[] = { Nan::Null(), results };
        callback->Call(2, argv, async_resource);
    }
    
    void HandleErrorCallback() {
        Nan::HandleScope scope;
        Local<Value> argv[] = { Nan::New(ErrorMessage()).ToLocalChecked(), Nan::Null() };
        callback->Call(2, argv, async_resource);
    }
    
private:
    SignatureTask* h_tasks;
    uint8_t* h_results;
    int numTasks;
};

// ============================================================================
// Async Worker for Merkle Root
// ============================================================================

class MerkleWorker : public Nan::AsyncWorker {
public:
    MerkleWorker(Nan::Callback *callback, Local<Array> txHashes)
        : AsyncWorker(callback) {
        
        numTx = txHashes->Length();
        h_hashes = new uint8_t[numTx * 32];
        
        for (int i = 0; i < numTx; i++) {
            Nan::MaybeLocal<Value> maybeHash = Nan::Get(txHashes, i);
            if (maybeHash.IsEmpty()) continue;
            
            Local<Value> hashVal = maybeHash.ToLocalChecked();
            if (hashVal->IsObject() && node::Buffer::HasInstance(hashVal)) {
                char* data = node::Buffer::Data(hashVal);
                size_t len = node::Buffer::Length(hashVal);
                memcpy(h_hashes + i * 32, data, len < 32 ? len : 32);
            }
        }
    }
    
    ~MerkleWorker() {
        if (h_hashes) delete[] h_hashes;
    }
    
    void Execute() {
        int ret = cudaMerkleRoot(h_hashes, numTx, h_root);
        if (ret != 0) {
            SetErrorMessage("CUDA Merkle computation failed");
        }
    }
    
    void HandleOKCallback() {
        Nan::HandleScope scope;
        
        Local<Object> rootBuffer = Nan::NewBuffer((char*)h_root, 32).ToLocalChecked();
        Local<Value> argv[] = { Nan::Null(), rootBuffer };
        callback->Call(2, argv, async_resource);
    }
    
    void HandleErrorCallback() {
        Nan::HandleScope scope;
        Local<Value> argv[] = { Nan::New(ErrorMessage()).ToLocalChecked(), Nan::Null() };
        callback->Call(2, argv, async_resource);
    }
    
private:
    uint8_t* h_hashes;
    uint8_t h_root[32];
    int numTx;
};

// ============================================================================
// NAN Method Exports
// ============================================================================

NAN_METHOD(VerifySignatures) {
    if (info.Length() < 2 || !info[0]->IsArray() || !info[1]->IsFunction()) {
        Nan::ThrowTypeError("Expected (tasks: Buffer[], callback: Function)");
        return;
    }
    
    Local<Array> tasks = info[0].As<Array>();
    Local<Function> cb = info[1].As<Function>();
    
    Nan::Callback *callback = new Nan::Callback(cb);
    Nan::AsyncQueueWorker(new VerifyWorker(callback, tasks));
}

NAN_METHOD(ComputeMerkleRoot) {
    if (info.Length() < 2 || !info[0]->IsArray() || !info[1]->IsFunction()) {
        Nan::ThrowTypeError("Expected (txHashes: Buffer[], callback: Function)");
        return;
    }
    
    Local<Array> hashes = info[0].As<Array>();
    Local<Function> cb = info[1].As<Function>();
    
    Nan::Callback *callback = new Nan::Callback(cb);
    Nan::AsyncQueueWorker(new MerkleWorker(callback, hashes));
}

// Synchronous versions for simple use cases
NAN_METHOD(VerifySignaturesSync) {
    if (info.Length() < 1 || !info[0]->IsArray()) {
        Nan::ThrowTypeError("Expected (tasks: Buffer[])");
        return;
    }
    
    Local<Array> tasks = info[0].As<Array>();
    int numTasks = tasks->Length();
    
    SignatureTask* h_tasks = new SignatureTask[numTasks];
    
    for (int i = 0; i < numTasks; i++) {
        Nan::MaybeLocal<Value> maybeTask = Nan::Get(tasks, i);
        if (maybeTask.IsEmpty()) continue;
        
        Local<Object> task = maybeTask.ToLocalChecked()->ToObject(Nan::GetCurrentContext()).ToLocalChecked();
        
        Local<Value> hashVal = Nan::Get(task, Nan::New("hash").ToLocalChecked()).ToLocalChecked();
        if (hashVal->IsObject() && node::Buffer::HasInstance(hashVal)) {
            memcpy(h_tasks[i].hash, node::Buffer::Data(hashVal), 32);
        }
        
        Local<Value> sigVal = Nan::Get(task, Nan::New("sig").ToLocalChecked()).ToLocalChecked();
        if (sigVal->IsObject() && node::Buffer::HasInstance(sigVal)) {
            size_t len = node::Buffer::Length(sigVal);
            h_tasks[i].sigLen = len < 72 ? len : 72;
            memcpy(h_tasks[i].sig, node::Buffer::Data(sigVal), h_tasks[i].sigLen);
        }
        
        Local<Value> pubVal = Nan::Get(task, Nan::New("pubKey").ToLocalChecked()).ToLocalChecked();
        if (pubVal->IsObject() && node::Buffer::HasInstance(pubVal)) {
            memcpy(h_tasks[i].pubKey, node::Buffer::Data(pubVal), 65);
        }
    }
    
    uint8_t* h_results = nullptr;
    int ret = cudaVerifyBatch(h_tasks, numTasks, &h_results);
    
    Local<Array> results = Nan::New<Array>(numTasks);
    if (ret == 0 && h_results) {
        for (int i = 0; i < numTasks; i++) {
            Nan::Set(results, i, Nan::New<Boolean>(h_results[i] == 1));
        }
        free(h_results);
    }
    
    delete[] h_tasks;
    info.GetReturnValue().Set(results);
}

// ============================================================================
// Module Init
// ============================================================================

NAN_MODULE_INIT(Init) {
    Nan::Set(target, Nan::New("verifySignatures").ToLocalChecked(),
        Nan::GetFunction(Nan::New<FunctionTemplate>(VerifySignatures)).ToLocalChecked());
    Nan::Set(target, Nan::New("computeMerkleRoot").ToLocalChecked(),
        Nan::GetFunction(Nan::New<FunctionTemplate>(ComputeMerkleRoot)).ToLocalChecked());
    Nan::Set(target, Nan::New("verifySignaturesSync").ToLocalChecked(),
        Nan::GetFunction(Nan::New<FunctionTemplate>(VerifySignaturesSync)).ToLocalChecked());
}

NODE_MODULE(bsv_cuda, Init)
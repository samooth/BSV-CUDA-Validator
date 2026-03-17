{
  "targets": [
    {
      "target_name": "bsv_cuda",
      "sources": ["src/native/bsv_cuda.cc"],
      "include_dirs": [
        "<!(node -e \"require('nan')\")",
        "/usr/local/cuda/include"
      ],
      "libraries": [
        "-L/usr/local/cuda/lib64",
        "-lcudart",
        "-L<(module_root_dir)/cuda",
        "-lbsv_cuda",
        "-Wl,-rpath,<(module_root_dir)/cuda"
      ],
      "cflags_cc": ["-std=c++20"],
      "conditions": [
        ["OS=='linux'", {
          "ldflags": ["-Wl,-rpath,/usr/local/cuda/lib64"]
        }]
      ]
    }
  ]
}
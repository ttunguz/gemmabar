from safetensors import safe_open
from glob import glob
import sys

paths = glob("/Users/simba/.cache/huggingface/hub/models--mlx-community--gemma-4-26b-a4b-it-4bit/snapshots/*/*.safetensors")
found = False
for path in paths:
    with safe_open(path, framework="np") as f:
        for k in f.keys():
            if "layers.3.experts" in k:
                print(k, f.get_tensor(k).shape)
                found = True
        if found: break

import sys, time; sys.path.insert(0, sys.argv[1])
import numpy as np, dikt_server as ds
sys.path.append(ds.__file__)
d = ds.Diktering()
from huggingface_hub import snapshot_download
import pianissimo_mlx
audio = pianissimo_mlx.read_audio(sys.argv[2])
print("ordlista:", ds.las_ordlista())
d.stream = object.__new__(type("F", (), {"stop": lambda s: None, "close": lambda s: None}))
d.chunks = [audio[:len(audio)//2], audio[len(audio)//2:]]
print("stop ->", d.stop())
d.stream = type("F", (), {"stop": lambda s: None, "close": lambda s: None})(); d.chunks = [np.zeros(1000, np.float32)]
print("för kort ->", d.stop())
print("stop utan inspelning ->", d.stop())

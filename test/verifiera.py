import sys, time, platform
t0 = time.perf_counter()
from huggingface_hub import snapshot_download
path = snapshot_download("KlangAI/pianissimo-sv-mlx-8bit")
sys.path.append(path)
import pianissimo_mlx
import mlx.core as mx
t_import = time.perf_counter()
model = pianissimo_mlx.load(path)
mx.eval(model.parameters())
t_load = time.perf_counter()
audio = pianissimo_mlx.read_audio(sys.argv[1])
dur = len(audio) / 16000
for i in range(3):
    t = time.perf_counter()
    r = pianissimo_mlx.transcribe(model, audio)
    print(f"körning {i+1}: {time.perf_counter()-t:.2f} s  ->  {r.text}")
print(f"\nImport: {t_import-t0:.2f} s, laddning: {t_load-t_import:.2f} s, ljudlängd: {dur:.1f} s")
print(f"MLX {mx.__version__}, minne toppvärde: {mx.get_peak_memory()/1e9:.2f} GB")

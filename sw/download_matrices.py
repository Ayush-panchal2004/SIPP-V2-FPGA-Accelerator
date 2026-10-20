import urllib.request
import urllib.error
import tarfile
import os
import io

matrices = [
    ("bcsstk01", "https://sparse.tamu.edu/MM/HB/bcsstk01.tar.gz"),
    ("nos1",     "https://sparse.tamu.edu/MM/HB/nos1.tar.gz"),
    ("steam1",   "https://sparse.tamu.edu/MM/Pothen/steam1.tar.gz"),
]

output_dir = "real_matrices"
os.makedirs(output_dir, exist_ok=True)

for name, url in matrices:
    print(f"Downloading {name}...")
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response:
            tar = tarfile.open(fileobj=io.BytesIO(response.read()), mode="r:gz")
            tar.extractall(path=output_dir)
            print(f"  Extracted to {output_dir}/{name}")
    except urllib.error.URLError as e:
        print(f"  Failed to download {name}: {e.reason}")
    except Exception as e:
        print(f"  Error processing {name}: {e}")

print("\nMatrix acquisition complete!")

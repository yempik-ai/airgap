#!/usr/bin/env python3
"""Build a synthetic MLX model directory, whole or broken in one named way.

The offline tests for AUDIT.md D1 and D2 need model folders that a real
download can produce and that this repository must judge correctly: a shard
still a git-lfs pointer, a shard the index names and that never arrived, and a
shard whose safetensors header describes more bytes than the file holds. All
three are cheap to write and none of them may be committed as a binary blob —
a shard has to be over 1 MB to get past the pointer test, so they are built
into a temporary directory at test time instead.

    python3 tests/fixtures/make-model.py <dir> [options]

      --shards N        how many shards (default 1; >1 also writes the index)
      --max-ctx N       max_position_embeddings in config.json (default 8192)
      --pointer N       write shard N as a 135-byte git-lfs pointer instead
      --drop N          do not write shard N at all (the index still names it)
      --truncate N      write shard N short of what its own header describes

Shard numbers are 1-based. The directory is created; anything already in it
with the same names is overwritten.
"""
import argparse, json, os, struct, sys

PAYLOAD = 1_200_000  # over the 1 MB every "is this a pointer?" test uses
POINTER = (
    "version https://git-lfs.github.com/spec/v1\n"
    "oid sha256:0000000000000000000000000000000000000000000000000000000000000000\n"
    "size 1200000\n"
)


def shard_name(i, n):
    return "model.safetensors" if n == 1 else "model-%05d-of-%05d.safetensors" % (i, n)


def write_shard(path, truncated):
    """One tensor of PAYLOAD bytes. `truncated` stops 4096 bytes short of the
    length the header declares — the shape a killed transfer leaves behind."""
    header = json.dumps({"weight": {"dtype": "F32", "shape": [PAYLOAD // 4],
                                    "data_offsets": [0, PAYLOAD]}}).encode()
    body = PAYLOAD - 4096 if truncated else PAYLOAD
    with open(path, "wb") as f:
        f.write(struct.pack("<Q", len(header)))
        f.write(header)
        f.write(b"\0" * body)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("dir")
    p.add_argument("--shards", type=int, default=1)
    p.add_argument("--max-ctx", type=int, default=8192)
    p.add_argument("--pointer", type=int, default=0)
    p.add_argument("--drop", type=int, default=0)
    p.add_argument("--truncate", type=int, default=0)
    a = p.parse_args()

    os.makedirs(a.dir, exist_ok=True)
    json.dump({"model_type": "qwen3_5", "max_position_embeddings": a.max_ctx,
               "num_hidden_layers": 1, "layer_types": ["full_attention"],
               "full_attention_interval": 1},
              open(os.path.join(a.dir, "config.json"), "w"))

    weight_map = {}
    for i in range(1, a.shards + 1):
        name = shard_name(i, a.shards)
        weight_map["weight_%d" % i] = name
        path = os.path.join(a.dir, name)
        if i == a.drop:
            continue
        if i == a.pointer:
            open(path, "w").write(POINTER)
            continue
        write_shard(path, truncated=(i == a.truncate))

    if a.shards > 1:
        json.dump({"metadata": {"total_size": PAYLOAD * a.shards},
                   "weight_map": weight_map},
                  open(os.path.join(a.dir, "model.safetensors.index.json"), "w"))
    print(a.dir)


if __name__ == "__main__":
    sys.exit(main())

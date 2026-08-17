#!/usr/bin/env bash
# bin/verify-model.sh — prove the download is complete, and show what is in it.
#
# It reads a few hundred kilobytes: the small text description at the front of
# each weights file, and config.json. It never loads the 20 GB of numbers and
# it never starts the server. Expect it to finish in under a second.
#
# Read docs/03-get-the-model.md for what each line of the output means.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

usage() {
  cat <<'EOF'
verify-model.sh — check the download, and explain what you downloaded.

WHAT IT DOES
  Opens each weights file just far enough to read its table of contents, and
  reports what is inside: how many pieces, how they are compressed, how the
  layers are split, and whether the model's fast-answer head is present.
  It reads only. It changes nothing, downloads nothing, and starts nothing.

WHAT IT COSTS
  Under a second of your time. A few hundred kilobytes of reading. No memory.

USAGE (run from the repo root)
  ./bin/verify-model.sh          check the model in MODEL_DIR
  ./bin/verify-model.sh --help   print this help

SETTINGS
  MODEL_DIR    which folder to check (a full path)
  PYTHON_BIN   which Python to use. Default: python3. It uses only what Python
               ships with — nothing is installed and no environment is needed.

WHAT YOU SHOULD SEE AT THE END
  verify PASS

IF IT SAYS FAIL
  Each failure line names the fix. The most common one by far is a weights file
  that is 135 bytes: that is a pointer file, not weights.
  Fix: docs/06-troubleshooting.md#lfs-pointers

READ NEXT
  docs/03-get-the-model.md
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") : ;;
  *) echo "verify-model.sh: I do not understand '$1'. Try: ./bin/verify-model.sh --help" >&2; exit 2 ;;
esac

if [ ! -f "$MODEL_DIR/config.json" ]; then
  echo "verify FAIL: no model at $MODEL_DIR" >&2
  echo "             run: ./bin/download-model.sh" >&2
  exit 1
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "verify FAIL: '$PYTHON_BIN' not found." >&2
  echo "             macOS ships python3 with the Xcode command line tools." >&2
  echo "             Install them with: xcode-select --install" >&2
  exit 1
fi

# Everything below is one Python program. It uses only the standard library:
# no pip, no virtual environment, no downloads.
MODEL_DIR="$MODEL_DIR" "$PYTHON_BIN" - <<'PYEOF'
import json, os, struct, sys, glob

d = os.environ["MODEL_DIR"]
fails = []

def fail(msg, *fix):
    fails.append((msg, fix))

# --- config.json -------------------------------------------------------------
cfg = json.load(open(os.path.join(d, "config.json")))
text = cfg.get("text_config", cfg)
mtype = cfg.get("model_type", "unknown")

print("model    %s" % os.path.basename(os.path.normpath(d)))
print("config   model_type = %s   (correct, not a typo -- Qwen3.8-27B is built on" % mtype)
print("         the qwen3_5 architecture family, the way Llama 3.1/3.2/3.3 all report")
print('         model_type "llama". Runtimes dispatch on model_type.)')

# --- layer split -------------------------------------------------------------
# Only the "full_attention" layers keep a growing record of the conversation.
# The others keep a fixed-size summary instead, which is why the memory cost of
# a long conversation here is a quarter of a same-size ordinary model's.
types = text.get("layer_types", [])
n_layers = text.get("num_hidden_layers", len(types))
n_full = sum(1 for t in types if t == "full_attention")
n_lin = sum(1 for t in types if t == "linear_attention")
interval = text.get("full_attention_interval", "?")
print("layers   %d = %d linear_attention (Gated DeltaNet) + %d full_attention" %
      (n_layers, n_lin, n_full))
print("         (full_attention_interval %s) -- only the %d hold a growing KV cache" %
      (interval, n_full))

# --- quantization ------------------------------------------------------------
q = cfg.get("quantization") or cfg.get("quantization_config") or {}
print("quant    %s-bit %s, group size %s" %
      (q.get("bits", "?"), q.get("mode", "?"), q.get("group_size", "?")))

# --- safetensors headers -----------------------------------------------------
# A safetensors file starts with 8 bytes saying how long its description is,
# then that many bytes of JSON listing every array in the file. Reading that
# costs a few hundred kilobytes. Reading the arrays themselves would cost 20 GB.
shards = sorted(glob.glob(os.path.join(d, "*.safetensors")))
if not shards:
    print("verify FAIL: no .safetensors files in %s" % d)
    print("             run: ./bin/download-model.sh")
    sys.exit(1)

total = quant = vision = mtp = 0
payload = 0
parsed = 0

for p in shards:
    size = os.path.getsize(p)
    if size < 1_000_000:
        fail("%s is %d bytes -- git-lfs pointer, not weights" % (os.path.basename(p), size),
             "run: cd '%s' && git lfs pull" % d)
        continue
    try:
        with open(p, "rb") as f:
            (hlen,) = struct.unpack("<Q", f.read(8))
            if hlen <= 0 or hlen > 200_000_000:
                raise ValueError("header length %d is not plausible" % hlen)
            header = json.loads(f.read(hlen).decode("utf-8"))
    except Exception as exc:
        fail("%s: could not read the file's table of contents (%s)" % (os.path.basename(p), exc),
             "the file is damaged. Delete the folder and run ./bin/download-model.sh again.")
        continue

    parsed += 1
    for name, meta in header.items():
        if name == "__metadata__":
            continue
        total += 1
        if name.endswith(".scales"):
            quant += 1
        if name.startswith("vision_tower.") or "visual" in name:
            vision += 1
        if ".mtp." in name or name.startswith("mtp."):
            mtp += 1
        offs = meta.get("data_offsets")
        if offs and len(offs) == 2:
            payload += offs[1] - offs[0]

pointer_note = "no git-lfs pointers" if parsed == len(shards) else "SOME FILES UNREADABLE"
print("shards   %d/%d headers parsed, %s" % (parsed, len(shards), pointer_note))
print("tensors  %d total | %d quantized | %d vision | %d MTP" % (total, quant, vision, mtp))

# --- the fast-answer head ----------------------------------------------------
# This checkpoint ships a small extra head that guesses several next tokens at
# once, so the main model can check a batch instead of producing one at a time.
# Stock mlx-lm deletes it on load. mlx-serve keeps it. That single fact is why
# this repo runs mlx-serve.
if mtp > 0:
    print("MTP head PRESENT -- the reason this stack runs mlx-serve, not stock mlx-lm")
else:
    fail("no mtp.* tensors found -- this checkpoint has no MTP head",
         "you can still run it, but the speed-up this repo describes will not apply.")

# --- size --------------------------------------------------------------------
# Text-only: the vision part is skipped at run time, so it costs disk but not
# memory while Claude Code is talking to the model.
vis_bytes = 0
for p in shards:
    if os.path.getsize(p) < 1_000_000:
        continue
    try:
        with open(p, "rb") as f:
            (hlen,) = struct.unpack("<Q", f.read(8))
            header = json.loads(f.read(hlen).decode("utf-8"))
        for name, meta in header.items():
            if name == "__metadata__":
                continue
            if name.startswith("vision_tower.") or "visual" in name:
                offs = meta.get("data_offsets")
                if offs and len(offs) == 2:
                    vis_bytes += offs[1] - offs[0]
    except Exception:
        pass

text_gb = (payload - vis_bytes) / 1073741824.0
print("size     %.1f GB of text-only weights on disk (the vision tower is skipped at" % text_gb)
print("         run time via --no-vision, so it costs disk but not memory)")

# --- cross-check against the publisher's own manifest ------------------------
mpath = os.path.join(d, "ARTIFACT-MANIFEST.json")
if os.path.exists(mpath):
    try:
        man = json.load(open(mpath))
        inv = man.get("tensor_inventory", {})
        exp_total = inv.get("physical")
        exp_quant = inv.get("quantized_logical")
        if exp_total is not None and exp_total != total:
            fail("expected %d tensors, found %d -- download is incomplete" % (exp_total, total),
                 "run: cd '%s' && git lfs pull" % d)
        if exp_quant is not None and exp_quant != quant:
            fail("expected %d quantized tensors, found %d -- download is incomplete"
                 % (exp_quant, quant),
                 "run: cd '%s' && git lfs pull" % d)
        if not fails:
            print("manifest matches ARTIFACT-MANIFEST.json (%d tensors, %d quantized)"
                  % (total, quant))
    except Exception as exc:
        print("  (ARTIFACT-MANIFEST.json could not be read: %s -- counts reported, not checked)" % exc)
else:
    print("  (no ARTIFACT-MANIFEST.json -- counts reported, not checked)")

print("")
if fails:
    for msg, fix in fails:
        print("verify FAIL: %s" % msg)
        for line in fix:
            print("             %s" % line)
    print("")
    print("See docs/06-troubleshooting.md")
    sys.exit(1)

print("verify PASS")
print("")
print("next: read docs/04-memory-safety.md, then ./bin/doctor.sh")
PYEOF

#!/usr/bin/env bash
# bin/catalog.sh — the one list of models this repository knows about.
#
# SOURCED by bin/detect-hardware.sh (and through it by every other script).
# Never run on its own. It defines one variable and three small functions and
# prints nothing.
#
# This file is the single source of truth for every per-model fact the scripts
# and the docs quote: which builds exist, where they live on huggingface.co,
# how big the download is, and how much of it is loaded into memory. Nothing
# else in bin/ carries a model size or a repository name of its own.
#
# One line per model:
#
#   key | huggingface repo | download GB | loaded GB | abliterated | note
#
#   key          the short name you type: ./bin/models.sh pull 27b-4bit
#   download GB  the real total of the .safetensors files, read from the
#                huggingface.co API in August 2026. Not an estimate.
#   loaded GB    what the server actually puts in memory: the text-only weights,
#                because the image-reading part is skipped at run time. Blank
#                means "not known separately" and the download size is used,
#                which is the safe direction to be wrong in.
#                  27b-5bit  19.1  MEASURED, by adding up the safetensors headers
#                                  of the checkpoint on disk (bin/verify-model.sh)
#                  27b-4bit  16.3  PUBLISHER-REPORTED, from the publisher's file
#                  27b-8bit  27.7  listing; not checked against files here
#                  9b-4bit    4.7  MEASURED (no vision tower in this checkpoint)
#                  27b-2bit   7.8  text-only checkpoints (no vision tower in the
#                  aeon      14.1  weight index), so download = loaded
#                Only the OrcaRouter builds carry the MTP speculative-decoding
#                head; every other entry was checked against its weight index
#                on huggingface.co and has none.
#   abliterated  yes = the publisher removed the refusal behaviour.
#                no  = safety training intact.
#
# The free memory each one needs is NOT stored here, on purpose. It depends on
# the Mac (context window, prefix cache), so it is computed by hw_rebudget in
# bin/detect-hardware.sh — the same function bin/serve.sh uses to decide whether
# to start. ./bin/models.sh list shows the result for the Mac it runs on.

CATALOG='
9b-4bit|keXjos/Qwen3.8-9B-mlx-4Bit|4.7|4.7|no|Smallest. A community distillation of Qwen3.8 into the Qwen3.5-9B architecture (empero-ai), not an official Qwen release. Safety training intact. No MTP head. Best for seeing the stack work, and the default on Macs under 32 GB.
27b-2bit|EgorKodin/Qwen3.8-27B-ABLITERATED-2bit-MLX-TextOnly|7.8|7.8|yes|Smallest abliterated 27B. 2-bit costs real quality — try it before trusting it. Text only, no MTP head.
27b-4bit-aeon|choppedgarlic/Qwen3.8-27B-AEON-ULTIMATE-UNCENSORED-4bit-MLX|14.1|14.1|yes|A different abliteration lineage (AEON) at 4-bit. Text only, no MTP head. Smaller than OrcaRouter 4-bit; fits under the GPU ceiling of a 24 GB Mac.
27b-4bit-stock|mlx-community/Qwen3.8-27B-4bit|15.0||no|The stock Qwen3.8-27B at 4-bit, safety training intact. No MTP head shipped in these files.
27b-4bit|chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-4bit|16.9|16.3|yes|OrcaRouter 4-bit. The default on a 32 GB Mac.
27b-5bit|chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-5bit|20.0|19.1|yes|OrcaRouter 5-bit. THE TESTED BUILD — every measured number in these docs came from it. The default from 36 GB.
27b-6bit|chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-6bit|23.0||yes|OrcaRouter 6-bit. Worth it only if you have memory to spare.
27b-8bit|chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-8bit|29.1|27.7|yes|OrcaRouter 8-bit. The default from 64 GB.
27b-8bit-stock|mlx-community/Qwen3.8-27B-8bit|27.5||no|The stock Qwen3.8-27B at 8-bit, safety training intact. No MTP head shipped in these files.
'

# The OrcaRouter builds share one repository name with the quantization as the
# suffix, which is what MODEL_QUANT selects between. Kept here so env.sh does
# not carry a second copy of the name.
# shellcheck disable=SC2034
CATALOG_ORCAROUTER_PREFIX="chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-MLX-"

# catalog_line <key>  — print the whole catalog line for a key, or nothing.
catalog_line() {
  printf '%s\n' "$CATALOG" | awk -F'|' -v k="$1" '$1 == k { print; exit }'
}

# catalog_field <key> <n>  — print field n (1-based) of the line for a key.
catalog_field() {
  catalog_line "$1" | cut -d'|' -f"$2"
}

# catalog_loaded_gb_for_dir <folder name>
# Print the loaded (text-only) size in GB for a model folder named after a
# catalog repository — the download size when the loaded size is not known
# separately — or nothing if the folder is not a catalog model. Callers fall
# back to measuring the shards on disk.
catalog_loaded_gb_for_dir() {
  printf '%s\n' "$CATALOG" | awk -F'|' -v d="$1" '
    NF >= 4 { n = split($2, p, "/"); if (p[n] == d) { print ($4 != "" ? $4 : $3); exit } }'
}

# catalog_download_gb_for_dir <folder name>
# Print the DOWNLOAD size in GB for a model folder named after a catalog
# repository, or nothing. This is the disk question, not the memory one: the
# vision tower and the tokenizer files land on disk even though the server
# never loads them, so MIN_DISK_GB is worked out from this figure and the
# memory guards from the loaded one above.
catalog_download_gb_for_dir() {
  printf '%s\n' "$CATALOG" | awk -F'|' -v d="$1" '
    NF >= 3 { n = split($2, p, "/"); if (p[n] == d) { print $3; exit } }'
}

> Archived: the desktop GPU box is gone — AI now comes from OpenCode Console (Jev). Kept for history only.

# Desktop vLLM host

1. Verify GPU: `nvidia-smi` (expect RTX 3090, driver ready).
2. Tailscale hostname must be `desktop`: `sudo tailscale set --hostname=desktop`.
3. Setup env:
   ```bash
   uv venv && source .venv/bin/activate
   uv pip install "vllm>=0.10"
   ```
4. Serve:
   ```bash
   vllm serve Qwen/Qwen3-8B-AWQ --host 0.0.0.0 --port 8000 \
     --max-model-len 16384 --max-num-seqs 16 \
     --enable-prefix-caching --gpu-memory-utilization 0.90
   ```
5. Verify: `curl http://localhost:8000/v1/models`.
6. Reboot note: re-run step 4 after every reboot/driver update.

Note: Windows Tailscale != WSL Tailscale — must run `tailscale up` INSIDE the WSL distro.
Set `--hostname=desktop` so the tailnet sees the Linux node by name.
Ensure same tailnet as `tailscale whoami` on CachyOS (same login/account).
If admin shows the Windows node but `tailscale status` on CachyOS lacks desktop,
that's the cause — the WSL distro never joined the tailnet.

# LLM gateway (exe.dev)

## Endpoint

```
http://169.254.169.254/gateway/llm/anthropic/v1/messages
```

- Anthropic Messages API shape. Header `anthropic-version: 2023-06-01`.
- **No API key needed** — the VM is authenticated by the gateway.
- Providers also available at `.../gateway/llm/{openai,fireworks}`.
- The documented hostname `https://llm.int.exe.xyz` is **not attached** to this VM
  (returns 403). Use the metadata IP above.

## Verified models

| Role | Model ID | Status |
|------|----------|--------|
| Experimenter, Judge | `claude-opus-4-8` | 200 OK |
| Worker | `claude-sonnet-4-6` | 200 OK |

## Raw curl

```bash
curl -s http://169.254.169.254/gateway/llm/anthropic/v1/messages \
  -H "content-type: application/json" -H "anthropic-version: 2023-06-01" \
  -d '{"model":"claude-opus-4-8","max_tokens":1024,
       "messages":[{"role":"user","content":"hello"}]}'
```

Usage is reported in the response `.usage` block (input/output/cache tokens).

## Headless `claude` CLI

```bash
ANTHROPIC_BASE_URL=http://169.254.169.254/gateway/llm/anthropic \
ANTHROPIC_API_KEY=implicit \
ANTHROPIC_MODEL=claude-sonnet-4-6 \
claude -p "…prompt…" --output-format text
```

Verified working. Use `--output-format json` to capture structured result + usage, and
`--output-format stream-json --verbose` to capture a full trace (tool calls included)
for the `traces/` record.

## Helpers in this repo

- `bin/llm.sh MODEL < prompt.json` — thin curl wrapper around the Messages API; prints
  the assistant text. Used by experimenter/judge for structured one-shot calls.
- The worker is driven by the `claude` CLI (it needs tools: file edits + bazel).

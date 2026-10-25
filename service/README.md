# 可选个人服务

手机的定位、计时、训练记录和已内置的微软语音无需该服务。服务仅供自己准备语音或主动请求 AI 跑后复盘使用。

## Python 本地服务

复制 .env.example 为 .env，填写自己的 SERVICE_ACCESS_TOKEN。需要生成语音时填写 AZURE_SPEECH_KEY、AZURE_SPEECH_REGION；需要 AI 时填写 AI_API_KEY、AI_BASE_URL、AI_MODEL。空值不会自动调用上游。

```sh
python service/server.py --host 127.0.0.1 --port 8787 --env-file service/.env
python -m unittest discover -s service -v
```

家里的局域网地址不能直接从外面的移动网络访问。户外 AI 复盘需要自己部署受访问令牌保护的 HTTPS 服务。

## Cloudflare Worker

在 cloud/ 中使用自己的 Cloudflare 账户部署 worker.mjs，并通过 Wrangler secrets 设置 SERVICE_ACCESS_TOKEN、AI_API_KEY、AI_MODEL，以及按需设置 AI_BASE_URL、AI_THINKING。配置不含作者账户 ID。Worker 只提供手动复盘，不提供运动中的语音合成。

```sh
node --test service/cloud/worker.test.mjs
```

不要把上游密钥放进 iPhone App 或 GitHub Pages。请独立管理访问令牌、速率限制和服务额度。

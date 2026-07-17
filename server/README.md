# Server（HuanHermes Host）

## Mock Host（推荐开发路径）

```bash
HUAN_BRIDGE_PORT=19810 HUAN_MGMT_PORT=19820 \
HUAN_BRIDGE_TOKEN=dev-bridge-token-change-me \
HUAN_MGMT_TOKEN=dev-mgmt-token-change-me \
python3 mock-host/mock_host.py
```

- Bridge: `ws://127.0.0.1:$HUAN_BRIDGE_PORT/bridge/ws?token=...`  
- Mgmt: `http://127.0.0.1:$HUAN_MGMT_PORT/api/v1`  

协议：`../docs/protocol/*`。

## 自研 Host

实现 `docs/guides/self-host-compat.md` 中的子集即可被 App 使用。  
`examples/` 仅是 **本仓** 配置字段示例，不是「去装某个外部项目」的说明。

## 注意

- 不要占用用户机器上已有服务的端口而不沟通  
- 不要把用户生产密钥写进示例文件提交 git  

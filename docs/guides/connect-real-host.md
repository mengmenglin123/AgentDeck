# 连接真实 Host（用户操作指南）

把 **HuanHermes App** 连到**你服务器上**的 Host（Mock 或实现本仓协议的自研服务）。

## 原则

- App 只做控制台；token 只填在 App 连接页。  
- **不要**为了联调去改/停用户已有线上服务。  
- 本仓库**不**要求安装任何特定第三方宿主；只要 Host 实现 `docs/protocol/*` 即可。

## 步骤

1. 在服务器启动 Host（开发可用本仓 Mock）：

```bash
HUAN_BRIDGE_PORT=19810 HUAN_MGMT_PORT=19820 \
HUAN_BRIDGE_TOKEN=<your-bridge-token> \
HUAN_MGMT_TOKEN=<your-mgmt-token> \
python3 server/mock-host/mock_host.py
```

2. App → Connect：填 Host IP、Bridge/Mgmt 端口、token、是否 TLS。  
3. Test & connect → Sessions → Chat。

## 会话路径双方言

App 自动探测：

- **project-scoped**: `/projects/{name}/sessions`  
- **flat**: `/sessions?project=`  

两种都是本仓协议支持的方言，不是「绑死某个外部产品」。

## 安全

- 公网务必 TLS 反代  
- 配对 URI **不含** token（见 Pairing 页）  
- 详见 `docs/security.md`

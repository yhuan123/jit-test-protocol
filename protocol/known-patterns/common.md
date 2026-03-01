# 通用 K8s 失败模式库

当测试用例 FAILED 时，test-executor agent 会自动匹配本文件中的模式进行诊断。
每个模式包含：ID、关键字（用于日志匹配）、原因、修复建议。

> Adapter 特有的失败模式见 `adapters/<name>/known-patterns.md`。

---

## Pattern-001: x509 证书错误

**关键字**: `x509: certificate signed by unknown authority`, `x509: certificate has expired`

**原因**: 集群或 registry 使用自签名证书，Pod 内不信任该 CA。

**修复建议**:
1. 确认 CA 证书已通过 ConfigMap 挂载到 Pod
2. 检查测试对象是否支持自定义 CA（trust-store workspace 等）
3. 如果是集群内 registry，检查 CA ConfigMap 是否存在
4. 验证证书未过期：`openssl x509 -in cert.pem -noout -dates`

**相关用例类型**: TLS 验证、自签名 CA、内部 registry

---

## Pattern-002: ImagePullBackOff

**关键字**: `ImagePullBackOff`, `ErrImagePull`, `Failed to pull image`

**原因**: 镜像拉取失败，可能是认证、网络或镜像不存在。

**修复建议**:
1. 检查 image pull secret 是否存在：`kubectl get secret -n <ns> | grep pull`
2. 检查 secret 中的认证信息是否正确（base64 解码验证）
3. 手动测试镜像拉取：`skopeo inspect docker://<image>`
4. 注意镜像架构匹配（amd64 镜像无法在 arm64 节点运行）

**相关用例类型**: 所有需要拉取镜像的用例

---

## Pattern-003: docker.io 超时

**关键字**: `i/o timeout`, `dial tcp: lookup registry-1.docker.io`, `docker.io`

**原因**: 集群网络无法访问 docker.io（国内集群常见）。

**修复建议**:
1. 使用内部 mirror 替代 docker.io
2. 检查测试资源中是否有 docker.io 镜像引用，替换为内部 registry
3. 将所需基础镜像预先推送到内部 registry

**相关用例类型**: 使用外部镜像的用例

---

## Pattern-004: 认证失败 (401/403)

**关键字**: `401 Unauthorized`, `403 Forbidden`, `UNAUTHORIZED`, `denied: access forbidden`

**原因**: Registry 认证失败，凭据不正确或过期。

**修复建议**:
1. 检查 Secret 中的 `.dockerconfigjson` 是否正确
2. 验证 base64 编码：`echo -n "user:pass" | base64`
3. 测试认证：`curl -u user:pass https://registry/v2/`
4. 检查 registry 中项目是否存在、用户是否有权限

**相关用例类型**: 需要 registry 认证的用例（push/pull private）

---

## Pattern-005: StorageClass 缺失

**关键字**: `no persistent volumes available`, `waiting for a volume to be created`, `storageclass.storage.k8s.io not found`

**原因**: PVC 请求了不存在的 StorageClass，或没有可用的 PV。

**修复建议**:
1. 检查可用 StorageClass：`kubectl get sc`
2. 部署合适的 Provisioner（NFS、local-path 等）
3. 检查 PVC 请求的 StorageClass 名称是否正确
4. 检查 PV 容量是否充足

**相关用例类型**: 需要持久化存储的用例（workspace 使用 PVC）

---

## 如何添加新模式

在 optimize 阶段，如果发现新的失败模式：

1. 确认该模式在至少 1 个用例中出现
2. 判断是通用 K8s 模式还是 Adapter 特有模式
   - 通用 → 添加到本文件
   - Adapter 特有 → 添加到 `adapters/<name>/known-patterns.md`
3. 按以下格式添加：

```markdown
## Pattern-XXX: [简短标题]

**关键字**: `keyword1`, `keyword2`

**原因**: [根因描述]

**修复建议**:
1. [步骤1]
2. [步骤2]

**相关用例类型**: [哪类用例会触发]
```

4. Pattern ID 递增，不重复
5. 展示给用户确认后再写入

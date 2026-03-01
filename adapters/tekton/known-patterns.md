# Tekton 特有失败模式库

本文件包含 Tekton TaskRun/PipelineRun 特有的失败模式。
通用 K8s 失败模式见 `~/.jit-test-protocol/protocol/known-patterns/common.md`。

---

## Pattern-T01: Hub Resolver 失败

**关键字**: `resolution request failed`, `error requesting resource from Hub`, `failed to fetch task`, `hub resolution error`

**原因**: Hub Resolver 无法解析指定的 Task/Pipeline 版本。

**修复建议**:
1. 确认 Hub Resolver 部署正常：`kubectl get deploy -n tekton-pipelines-resolvers`
2. 确认 Hub 上存在该版本：检查 catalog repo 的 tag/release
3. 检查 Resolver 配置：`kubectl get cm hub-resolver-config -n tekton-pipelines-resolvers -o yaml`
4. 检查网络：Resolver 需要访问 Hub API

**相关用例类型**: 使用 Hub Resolver 引用 Task/Pipeline 的用例

---

## Pattern-T02: crane 循环覆盖

**关键字**: `manifests | length`, `index append`, `crane index`

**原因**: `crane index append` 在循环中调用时，每次从空 index 开始，最后一次覆盖之前所有结果。manifest 数量不等于源镜像数量。

**修复建议**:
1. 一次性传入所有 `-m` 参数，而非循环调用
2. 验证命令：`skopeo inspect --raw <target> | jq '.manifests | length'` 应等于源镜像数量

**相关用例类型**: merge-image Task 的所有合并用例

---

## Pattern-T03: 重复源镜像导致 NOT_FOUND

**关键字**: `NOT_FOUND: artifact`, `not found`, `pushing image`, `manifests/latest`

**原因**: `crane index append` 传入两个相同的源镜像时，内部构建 index 引用了一个不存在的 manifest digest，导致 push index 时 registry 返回 NOT_FOUND。

**修复建议**:
1. 在 Task 脚本中对 sourceImages 做去重（`sort -u`）
2. 如果不去重，至少在日志中 WARNING 提示存在重复源镜像
3. 验证：传入去重后的镜像列表重跑

**相关用例类型**: merge-image Task 中 sourceImages 包含重复条目的场景

---

## Pattern-T04: Affinity Assistant 调度冲突

**关键字**: `PodScheduled`, `0/N nodes are available`, `affinity-assistant`, `node affinity conflict`

**原因**: Tekton 默认开启 coschedule（affinity assistant），强制 PipelineRun 中共享 workspace 的 TaskRun Pod 调度到同一节点。当使用 nodeSelector 指定不同架构节点时，两个约束冲突导致调度失败。

**修复建议**:
1. 如果使用 NFS（ReadWriteMany），可临时关闭 coschedule：
   `kubectl patch cm feature-flags -n tekton-pipelines --type merge -p '{"data":{"coschedule":"disabled"}}'`
2. 执行完后恢复：
   `kubectl patch cm feature-flags -n tekton-pipelines --type merge -p '{"data":{"coschedule":"workspaces"}}'`
3. 或使用不依赖 affinity assistant 的 StorageClass

**相关用例类型**: 跨节点调度的 PipelineRun（多架构构建等）

---

## Pattern-T05: buildah SETFCAP 内核不兼容

**关键字**: `Error during unshare(CLONE_NEWUSER)`, `SETFCAP`, `Invalid argument`, `unshare`

**原因**: buildah 在低版本内核（如 CentOS 7 kernel 3.10）上无法使用 user namespace，即使使用 `--isolation chroot` 也因 unshare 先于 isolation 执行而失败。

**修复建议**:
1. 使用 RHEL 8+（kernel 4.18+）或 Ubuntu 20.04+ 节点
2. 或以 privileged 模式运行 Pod：`securityContext.privileged: true`
3. 检查节点内核版本：`uname -r`

**相关用例类型**: 使用 buildah Task 的构建用例

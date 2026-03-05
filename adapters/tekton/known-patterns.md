# Tekton 特有失败模式库

本文件包含 Tekton TaskRun/PipelineRun 特有的失败模式。
通用 K8s 失败模式见 `~/.jit-test-protocol/protocol/known-patterns/common.md`。

---

## Pattern-T01: Hub Resolver 参数错误

**关键字**: `resolution request failed`, `error requesting resource from Hub`, `failed to fetch task`, `hub resolution error`, `TaskRunResolutionFailed`, `invalid value`, `type`

**原因**: Hub Resolver 无法解析指定的 Task/Pipeline。常见子场景：
1. **版本不存在**: Hub 上无该 Task/Pipeline 版本
2. **参数名错误**: 使用了无效参数（如 `type: task`），正确应为 `kind: task`
3. **Resolver 不可用**: Hub Resolver 部署异常或网络不通

**有效参数**: `catalog`、`kind`、`name`、`version`

**修复建议**:
1. 确认参数格式正确：
   ```yaml
   taskRef:
     resolver: hub
     params:
     - name: catalog
       value: catalog
     - name: kind
       value: task
     - name: name
       value: helm-upgrade
     - name: version
       value: "0.1"
   ```
2. 确认 Hub Resolver 部署正常：`kubectl get deploy -n tekton-pipelines-resolvers`
3. 确认 Hub 上存在该版本：检查 catalog repo 的 tag/release
4. 检查 Resolver 配置：`kubectl get cm hub-resolver-config -n tekton-pipelines-resolvers -o yaml`

**相关用例类型**: 所有使用 Hub Resolver 的 TaskRun/PipelineRun

---

## Pattern-T02: Affinity Assistant 调度冲突

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

## Pattern-T03: buildah SETFCAP 内核不兼容

**关键字**: `Error during unshare(CLONE_NEWUSER)`, `SETFCAP`, `Invalid argument`, `unshare`

**原因**: buildah 在低版本内核（如 CentOS 7 kernel 3.10）上无法使用 user namespace，即使使用 `--isolation chroot` 也因 unshare 先于 isolation 执行而失败。

**修复建议**:
1. 使用 RHEL 8+（kernel 4.18+）或 Ubuntu 20.04+ 节点
2. 或以 privileged 模式运行 Pod：`securityContext.privileged: true`
3. 检查节点内核版本：`uname -r`

**相关用例类型**: 使用 buildah Task 的构建用例

---

## Pattern-T04: Tekton 参数类型与命名陷阱

**关键字**: `param types don't match the user-specified type`, `Chart.yaml not found in /workspace/source/.`

**原因**: Tekton Task 参数存在两类常见陷阱：
1. **类型不匹配**: Task 定义参数为 `type: array`，但传入了 `string`。常见于 `ociRepos`、`valuesFiles` 等参数
2. **参数名不一致**: Task 实际参数名与直觉不同（如 chart-build-push 用 `chartPath` 而非 `chartDir`），传入不存在的参数名会被 Tekton **静默忽略**，使用默认值

**常见踩坑参数**:
| Task | 参数 | 类型 | 易错写法 |
|------|------|------|---------|
| chart-build-push | `ociRepos` | array | 误传 string `demo-app`，需完整引用 `registry/project/chart:tag` |
| chart-build-push | `chartPath` | string | 误写为 `chartDir` |
| helm-upgrade | `valuesFiles` | array | 误传 JSON string `'["./file.yaml"]'` |

**修复建议**:
1. array 类型参数使用 YAML 列表格式：
   ```yaml
   - name: ociRepos
     value:
     - devops-harbor.alaudatech.net/helm-test/demo-app:0.3.0
   - name: valuesFiles
     value:
     - ./deploy/values-prod.yaml
   ```
2. 不确定参数名时，查看 Task 定义：`kubectl get taskrun <name> -o jsonpath='{.status.taskSpec.params}'`

**相关用例类型**: 所有使用 Hub Resolver 引用 Task 的用例

---

## Pattern-T05: Helm --wait 需要 replicasets 权限

**关键字**: `replicasets.apps is forbidden`, `cannot list resource "replicasets"`

**原因**: Helm `--wait` 需要 list replicasets 来检查 Deployment 就绪状态。最小 RBAC Role 仅包含 Deployment/Service/ConfigMap CRUD 时，会在 wait 阶段失败。

**修复建议**:
1. 最小 RBAC Role 需增加：`apps/replicasets: get,list,watch`
2. 或使用 `wait: false` 跳过就绪检查

**相关用例类型**: 使用受限 ServiceAccount 执行 helm-upgrade 且 wait=true 的用例

---

## Pattern-T06: git-clone basic-auth Secret 格式

**关键字**: `could not read Username`, `fatal: unable to access`, `Authentication failed`

**原因**: git-clone Task 的 basic-auth workspace 需要 Secret 包含 `.gitconfig` 和 `.git-credentials` 文件键，类型为 Opaque。使用 `kubernetes.io/basic-auth` 类型 + `username`/`password` 键不会生效。

**修复建议**:
1. Secret 格式：
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: git-basic-auth
   type: Opaque
   stringData:
     .gitconfig: |
       [credential "https://gitlab.example.com"]
         helper = store
     .git-credentials: |
       https://user:token@gitlab.example.com
   ```

**相关用例类型**: 使用 git-clone basic-auth workspace 的用例

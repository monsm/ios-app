# 内置 three.js 说明

这三个文件是 three.js 0.160.0 的**原样副本**（unpkg 下载），
用于把 3D demo 做成**完全离线单文件** —— 之前的版本从 CDN 拉，
用户网络不通就会黑屏。

| 文件 | 来源 | 大小 |
|---|---|---|
| `three.js` | `three@0.160.0/build/three.module.min.js` | ~655 KB |
| `orbit.js` | `three@0.160.0/examples/jsm/controls/OrbitControls.js` | ~29 KB |
| `room.js` | `three@0.160.0/examples/jsm/environments/RoomEnvironment.js` | ~4 KB |

构建脚本 `tools/build-demo.js` 会把它们内联进 `docs/redesign/lock-abc-demo.html`。

许可证：three.js 为 MIT。

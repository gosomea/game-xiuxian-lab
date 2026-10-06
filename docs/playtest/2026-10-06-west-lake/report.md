# 西湖夕照 · 穿云运行记录

日期：2026-10-06。Godot 4.6 stable，macOS / Apple M4 Pro，Compatibility / OpenGL。采用 CLI 场景树测试和实际窗口截图，没有 Godot MCP。场景最后一项登记为 exploring，当前按 WIP 保存：可游览与穿云，退出资源诊断仍存在。

## 实现范围

压缩西湖湖面、东岸杭州街区、环湖步道、白堤断桥/孤山、苏堤六桥、三座湖心岛/三潭石塔、雷峰塔与保俶塔、周边山景。天空有夕阳，水纹、云纹、云团、游船与鸟有表现运动。固定云层 32–48 米，空域到 180 米，落水回湖滨。

人物、七段 clip 和移动数值原样复用现役 Swordsman。默认受限透视；V 切正交，1–4 四种共享 CameraRig 模式，RMB/Q/E/滚轮均使用共享入口。M 俯览对准湖心，地面俯览隐藏云片以读地理；高空仍显示云海。风格使用纸色、墨线和简化色阶，没有写实金属高光。

## 验收

| 验收项 | 结果 | 证据 |
|---|---|---|
| Tier 0 门禁与负向控制 | PASS | [检查](checks.txt)，27/27 负向控制 |
| 全量运行测试 | PASS | 1658 通过 / 0 失败，无头完整套件日志无脚本/引擎错误 |
| 十场景共享疾跑 | PASS | 150 断言；本场步行 1.25、疾跑 2.25 m/s |
| 十场景共享跳跃/御剑 | PASS | 333 断言；本场飞行 12、升/降 ±7 m/s |
| 西湖专项 | PASS | 33 断言：岸/堤/桥/三岛碰撞、水域空洞、四镜头、两投影、从出生点连续真实 Space 升空越过云顶、镜头高度、四处收剑降落、落水与复位 |
| 真实两级目录/十项返回 | PASS | [目录验收](navigation-checks.txt)，失败 0，计数 10/10 |
| 最终窗口截图与输入 | PASS，范围见下 | [窗口日志](window-checks.txt)，9 组共 74 条断言；近景头脚、Shift 疾跑、Space 起跳、真实进入与 Esc 返回 |
| 最终窗口持续直飞 | 未完成复验 | 早期窗口按键分别到 39/61 m；后续一次云中操作被失焦清输入中断，只到 1.1 m，保留 [中断记录](window-ascent-interruption.txt)。按有界验收纪律转用独立状态证据：完整套件仍从地面真实连续输入升到云上；最终云中/云上截图用明确标注的构图定位 |
| 窗口退出资源诊断 | FAIL，未解决 | 所选窗口退出各报告四条 `Texture with GL ID ... leaked 349524 bytes`。之前湖岸回归也有同类问题，具体资源归属未定位，不能称为引擎问题或无诊断通过 |
| 直接无头退出控制 | 有诊断 | [控制](headless-shutdown-controls.txt)：本场及旧湖岸直接 `--quit-after 80` 都报 dummy renderer 空材质，旧庭院无此诊断。完整套件主动清理场景后没有诊断；直接退出差异仍未解决 |
| 风格与手感是否达到最终目标 | 需人工判断 | 已读真实截图；技术断言不能替使用者判断美术与连续手感 |

最终天空、云团、云层、人物材质均由窗口实际编译并渲染，无 shader 编译错误。云团材质取消无用的覆盖层，云片参数只在值变化时更新并保留资源引用；最终窗口不再报告中间阶段的空材质诊断。不能由此推导直接无头退出也已修复。

全量测试在最后云团轮廓调整前通过；最后调整只改变不参与物理的云团尺寸，同源岸、桥、岛碰撞、输入和镜头代码不变；调整后重导入并重新做实际窗口取证。云中遮蔽读回为 1.0，61 m 为 0.0。

## 实际画面

- [最终地面夕照](ground-v5.png)：夕阳位于西山背后，湖滨人物与码头、水面、花柳、堤岛都可观察。
- [最终云上](above_view-v5.png)：61 m，镜头焦点随人物升高，云海与湖景在脚下。**构图定位截图，不能当作按键飞行证据。**
- [云中](cloud_view-v4.png)：39 m，柔和遮蔽保留 HUD 与人物轮廓。**构图定位截图。**
- [全景](panorama-v4.png)、[近景](close-v4.png)、[疾跑](run-v4.png)、[跳跃](jump-v4.png)、[塔前](leifeng-v4.png)、[小窗口](small-v4.png)。塔前是构图定位，真实降落由专项物理测试验证。小窗口请求 960×640，实际内容 960×600，按钮可换行，头脚均在取景内。
- 前轮按键升空 [云中](cloud.png)、[云上](above.png) 与 [按键日志](early-window-ascent.txt) 保留；初轮偏东的俯览、无夕阳的正交近景、天空被雾冲淡、透明云团和轮廓调整等截图全部保留比较。

最终地面采样 88 draw calls / 254670 primitives，云上 90 / 247798；这是单帧计数，不是 FPS 压测或性能保证。程序环境 113648 三角形，16 组同源步行网格、39 个碰撞盒。

## 结论与边界

移动目录已增加可运行的最后一个综合场景，地面、岛台和云层组合已能观察。杭州与西湖使用压缩地理和简化建筑，未复原整个城市、真实比例或建筑室内；未新增任务、交通、NPC 或动态昼夜。当前画面保持色块/纸色的 3 渲 2 方向，植物、云团和建筑仍有程序几何感，不声称达到参考画风的最终质量。退出问题使本轮按 WIP 提交，进入、游览、能力状态与返回验收已完成。

## 复验

```sh
python3 tools/art/build_west_lake_sunset.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path src --import
python3 tools/verify/run_all.py --with-tests
./run.command res://levels/experiments/character_movement/west_lake_sunset.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path src --script res://tests/west_lake_sunset_playtest.gd -- --shot=ground --output=/absolute/path/new-preview.png
```

截图脚本支持 ground / panorama / close / run / jump / cloud / above / cloud_view / above_view / leifeng，以及 `--small`。cloud/above 是真实持续按键；cloud_view/above_view/leifeng 是标注的构图定位。窗口操作要保持 Godot 焦点；失焦清输入是共享移动能力的预期行为。

# 水墨湖岸样板：运行与画面记录

日期：2026-10-05。Godot 4.6.stable.official.89cea1439 / Apple M4 Pro / Compatibility OpenGL。

## 交付范围

新增角色移动目录的第九个子实验「水墨湖岸样板」，状态 exploring。场景原样复用现役人物、七段动作、三项移动能力与完整输入入口。新增原创程序环境 GLB、布局、纸纹与湖面 shader、日轮 SVG；没有引入第三方素材。源与导出见[台账](../../art/ink_lakeside_sample/asset_ledger.md)。

## 运行结果

| 验收点 | 结果 | 依据 |
|---|---|---|
| Tier 0 门禁、负向控制 | PASS | [检查输出](checks.txt)，负向控制 27/27 |
| 全量运行测试 | PASS | 1571 通过 / 0 失败，日志无脚本或引擎错误 |
| 九场景疾跑 | PASS | 135 通过 / 0 失败，新样板走速 1.25、疾跑 2.25 m/s |
| 九场景跳跃与御剑 | PASS | 300 通过 / 0 失败，新样板飞行 12、上升 7、下降 -7 m/s |
| 新样板地形与取景 | PASS | 14 通过 / 0 失败：岸、桥、岛、平台碰撞；水域无隐形地面；落水回收；真实收剑降落岛与高台；近景头脚完整；共享人物材质不被修改 |
| 真实目录进入与 Esc 返回 | PASS | 六组窗口脚本均检查实际场景路径 |
| 窗口截图与操作 | PASS | 默认/近景/疾跑/跳跃/御剑/小窗口分别 8/8/9/9/10/8 条断言通过，共 52 条；[窗口日志](window-checks.txt) |
| 窗口退出资源诊断 | FAIL，未解决 | 返回移动目录后退出，六组均报告四条 `Texture with GL ID ... leaked 349524 bytes`；脚本退出码为 0，不代表退出无诊断 |
| 最终审美与连续手感 | 未验证 | 需使用者实际看画面、试玩，不由技术断言替代 |

直接启动新场景、推进 80 帧后退出的控制没有诊断；旧青玉场景启动后返回移动目录再退出也报告两条同类诊断。此证据只说明该流程已有同类问题。已尝试退出前释放场景、调整退出时机及字体缓存清理，未消除诊断；字体缓存清理尝试未保留到正式代码。2026-10-06 当时按 WIP 保存。

## 2026-10-09 退出复验

| 验收项 | 结果 | 证据 |
|---|---|---|
| 窗口：目录进入、默认断言、Esc 返回后退出 | PASS | `ink_lakeside_sample_playtest.gd --shot=default`，断言全部 PASS，日志无 `leaked` |
| 无头直接退出 | PASS | `--headless --quit-after 40` 无空材质 |
| 移动目录单独退出 | PASS | 窗口 `--quit-after 40` 打开移动目录，无纹理泄漏 |

四条 `349524` 字节纹理是 256×256 RGBA8 加完整 mip。返回目录会再次装载目录，于是两次 `load()` 全部子场景留下四条；目录里只装载一次是两条，和当初青玉对照一致。修复是目录校验改用 `ResourceLoader.exists()`，不再 `load()`。无头空材质是 dummy renderer 在 `duplicate()` 导入人物材质时查询到空 RID；无头跳过该调色复制后，直接退出无此诊断。窗口里的调色复制仍保留。

无头 dummy renderer 不支持本轮自定义材质的完整释放路径，初轮报空材质诊断；物理验收采用普通材质后日志干净。实际 shader 编译和像素来自窗口渲染，不能用无头结果评价 shader。

## 画面

- [默认全景](default.png)：暖纸、分层灰青山水、五层塔、白墙墨瓦和淡粉树。
- [人物近景](close.png)：现役人物与场景实例材质，取景偏移随缩放收敛，保留头部和脚底。
- [疾跑](walk.png)（文件名为 walk，实际注入 D + Shift）、[跳跃](jump.png)、[御剑](flight.png)：操作经真实按键事件进入，读取实际物理状态后截图。
- [小窗口](small.png)：请求 960×640 窗口，项目保持 16:10 内容，实际视口 960×600；人物完整，按钮与提示未溢出。
- 首轮[全景](first-pass.png)、第二轮[全景](second-pass.png)、修复前[近景裁脚](close-before-framing.png)保留比较。首轮湖面偏暗，远山纸纹形成条纹；现版修正采样与湖色，扩展前景岸面，移动日轮，修复缩放裁脚。

默认窗口采样为 37 draw calls / 183629 primitives，御剑为 47 / 184087（含现役角色与飞剑）。这是单帧渲染计数，不是持续帧率或性能压测结论。

## 当前结论

新样板已能在共享操作下观察岸、桥、塔、小岛和远山，色板与轮廓明显区别于原青玉样板。环境仍是简化程序几何，花树枝叶、屋瓦与墨线的手绘变化需要进一步探索；未声明达到参考图的最终质量。塔和民居无室内，远山不可探索，不代表地图模块完成。

## 复验

```sh
python3 tools/art/build_ink_lakeside_sample.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path src --import
python3 tools/verify/run_all.py --with-tests
./run.command res://levels/experiments/character_movement/ink_lakeside_sample.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path src --script res://tests/ink_lakeside_sample_playtest.gd -- --shot=flight --output=/absolute/path/flight.png
```

shot 支持 default / close / walk / jump / flight；`--small` 单独指定小窗口。截图取证后的退出仍会出现上表已记录的诊断。

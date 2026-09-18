class_name CameraRigConfig
extends Resource

## 镜头装配的投影与参数配置（Resource，不参与模式组合爆炸）。
##
## 投影方式（正交 / 有限透视）与跟随行为分开：本资源只描述投影、距离、俯角、
## 缩放范围、焦点收缩与 modifier 系数；模式 Capability 决定"怎么跟"，本资源决定
## "用什么镜头看"。
## 依据 notes/implemented/tech/2026-09-18-composable-lab-assembly-contract.md 第 3 节。

## 相机投影：正交（默认，2.5D 尺度稳定）或透视。
@export var projection: Camera3D.ProjectionType = Camera3D.PROJECTION_ORTHOGONAL
## 正交 size：宽或高的直径（米），取决于 keep_aspect；相机默认 KEEP_HEIGHT。
@export var size: float = 24.0
@export var size_min: float = 8.0
@export var size_max: float = 44.0
@export var zoom_step: float = 2.0
## 透视模式下的视场角（度）与缩放距离范围；透视滚轮调 distance，不改 size。
@export var fov: float = 60.0
@export var distance_min: float = 6.0
@export var distance_max: float = 60.0
@export var distance_step: float = 1.5
## 裁剪面（米）：由 executor 统一写，模式不得重复写。
@export var near: float = 0.1
@export var far: float = 220.0

## 初始镜头模式与 fixed_follow 参数预设；两者都是数据，不是 Capability。
@export var start_mode: String = "fixed_follow"
@export var follow_preset: String = "hard"

## 可用模式子集（数字键 1..N 按此顺序对应；空 = 只有 fixed_follow）。
## 非 lab 场景默认只挂 fixed_follow，不抢场景自己的数字快捷键。
@export var mode_choices: PackedStringArray = PackedStringArray(["fixed_follow"])
## 输入开关：默认全关，避免独立场景被镜头包抢掉实验按键；lab 显式打开。
## 1..N 选模式（需同时配 mode_choices）。
@export var enable_mode_selection_keys: bool = false
## Tab 循环 fixed_follow 预设。
@export var enable_preset_key: bool = false
## Z / X 键盘缩放（滚轮与按钮不受此开关限制）。
@export var enable_zoom_keys: bool = false
## 滚轮缩放；GUI 已消费的滚轮不会到达镜头包。
@export var enable_zoom_wheel: bool = true
## Q / E：只在 quarter_turn（离散 ±90°）与 orbit（连续）下消费，其余模式放行给场景。
@export var enable_yaw_keys: bool = true
## 未归属 RMB 消费策略（默认关闭 = 现状：镜头包不抢场景按键）。
## 显式开启后：非 orbit 模式在 UI 未占用的世界区域消费 RMB press / release，但不捕获、
## 不写 Input.set_mouse_mode、不写 look_delta；orbit 的 RMB press 在 UI 未占用时尽早进入捕获。
## UI 上方的右键由 GUI 优先，本包不劫持。避免未消费的右键泄漏为编辑器嵌入 Game 视图的上下文操作。
## 依据 notes/implemented/tech/2026-09-18-composable-lab-assembly-contract.md §2「未归属 RMB 消费策略」。
@export var consume_unowned_rmb: bool = false
## 透视模式的视场角由 fov 与 distance 共同决定；滚轮调 distance（见下）。
@export var fov_is_configurable: bool = false

## 相机绕焦点的球面参数。
@export var yaw_degrees: float = -35.0
@export var pitch_degrees: float = 42.0
@export var distance: float = 16.0
## orbit 的俯角限幅（度）：受限视角，不做全球自由旋转。
@export var pitch_min_degrees: float = 12.0
@export var pitch_max_degrees: float = 78.0
## 连续偏航角速度（度/秒，orbit）与 quarter_turn 单步角度（度）。
@export var yaw_speed_degrees: float = 90.0
@export var turn_step_degrees: float = 90.0

## overview 平移与回中。
@export var pan_speed: float = 1.0
@export var pan_distance_max: float = 18.0
@export var recenter_time: float = 0.35

## 固定跟随的时间常数（秒）：越大越拖。
@export var smooth_time: float = 0.35
## 死区半宽 / 半高（米）：目标在焦点周围这个矩形内移动时相机不动。
@export var deadzone_half_width: float = 4.0
@export var deadzone_half_height: float = 2.5
## 前视：按目标水平速度提前的秒数与限幅（米）。
@export var lookahead_time: float = 0.45
@export var lookahead_max: float = 5.0
@export var lookahead_smooth_time: float = 0.3

## modifier：高度 / 速度自适应距离偏移（executor 按数据叠加，不是独立 Capability）。
@export var height_reference_y: float = 0.0
@export var height_distance_bias: float = 0.0
@export var height_bias_max: float = 6.0
@export var speed_distance_bias: float = 0.0
@export var speed_bias_max: float = 4.0

## 取景偏移（米）：加到目标 snapshot 上，用于对准人物胸部或其它场景的构图偏移。
## 速度差分仍用目标真实位置，不受此处影响。
@export var focus_offset: Vector3 = Vector3.ZERO

## 焦点收缩：庭院等有界场地的构图保持。
## x/z 打开后始终夹取；y 默认不夹取，避免把高空御剑的镜头压回地面——
## 需要地平构图的 2.5D 场地（庭院）显式打开 focus_clamp_y_enabled 并把 min/max y 设为 0；
## 开放空域（群山 / 御剑航线）打开 x/z、关闭 y，或用场景的 3D bounds 打开 y。
@export var focus_clamp_enabled: bool = false
@export var focus_clamp_y_enabled: bool = false
@export var focus_clamp_min: Vector3 = Vector3.ZERO
@export var focus_clamp_max: Vector3 = Vector3.ZERO

## 模式切换的平滑时间（秒）；0 表示瞬切。混合期输入照常累积、不跨模式积压。
@export var transition_time: float = 0.25
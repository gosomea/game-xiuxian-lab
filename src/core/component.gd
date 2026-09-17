class_name Component
extends Node

## 纯数据容器基类。
##
## 铁律：只存数据，不做决策（根 AGENTS.md 约定 1，verify-component-purity 机械兜底）。
## 允许：字段、派生值计算、数据存取方法、数据变化 signal。
## 禁止：每帧回调、行为分支、引用 TagRegistry/TimeKeeper/Input/Engine、遍历场景树。

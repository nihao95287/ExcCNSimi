# 项目重构计划 - 基于事件总线的模块化架构

## 设计理念

### 核心原则
- **事件总线模式**：通过EventBus实现模块间解耦通信
- **模块化设计**：每个Manager职责单一，便于团队协作
- **可扩展性**：未来新增季节、作物、建筑只需添加新模块

---

## 模块化架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                         EventBus (自动加载)                        │
│                    Global Signals - 无状态                         │
└─────────────────────────────────────────────────────────────────┘
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        ▼                         ▼                         ▼
┌───────────────┐        ┌───────────────┐        ┌───────────────┐
│   Managers     │        │   Entities    │        │      UI       │
│   (业务逻辑)   │        │   (实体行为)  │        │   (仅订阅)    │
└───────────────┘        └───────────────┘        └───────────────┘
        │                         │
        ▼                         ▼
┌───────────────┐        ┌───────────────┐
│ResourceManager│        │    Villager   │
│StockpileManager│        │ ResourceNode │
│SeasonManager │        │   ItemDrop    │
│CropManager  │        │   Animal      │
│BuildingManager│        └───────────────┘
└───────────────┘
```

---

## Manager模块职责

### 1. ResourceManager (资源管理)
- **订阅事件**：item_stored
- **发布事件**：resources_updated
- **职责**：
  - 资源统计（wood, stone, meat）
  - 资源类型定义和名称转换

### 2. StockpileManager (仓库管理)
- **订阅事件**：item_dropped, villager_idle
- **发布事件**：stockpile_created, stockpile_updated
- **职责**：
  - 仓库格子管理（stockpile_cells数组）
  - 仓库区域划定
  - 自动入库逻辑

### 3. ItemManager (物品管理)
- **订阅事件**：item_dropped, villager_task_completed
- **发布事件**：item_registered, item_unregistered
- **职责**：
  - 未搬运物品追踪（unhauled_items）
  - 已入库物品追踪（stockpile_items）
  - 物品注册/注销

### 4. SeasonManager (季节系统) [未来扩展]
- **订阅事件**：无
- **发布事件**：season_changed, day_changed
- **职责**：
  - 季节状态（春/夏/秋/冬）
  - 日期/时间推进
  - 季节效果影响

### 5. CropManager (作物管理) [未来扩展]
- **订阅事件**：season_changed
- **发布事件**：crop_ready, crop_harvested
- **职责**：
  - 作物生长状态
  - 种植/收获逻辑
  - 季节对作物影响

### 6. BuildingManager (建筑管理) [未来扩展]
- **订阅事件**：resources_updated, stockpile_created
- **发布事件**：building_placed, building_destroyed
- **职责**：
  - 建筑状态管理
  - 建筑成本检查
  - 建筑效果应用

---

## 事件定义 (EventBus Signals)

### 资源类事件
```gdscript
# 物品入库（从搬运状态转入仓库）
signal item_stored(item_type: int, amount: int)

# 资源统计更新
signal resources_updated(wood: int, stone: int, meat: int)
```

### 物品类事件
```gdscript
# 物品掉落（资源节点被depletion时）
signal item_dropped(item: Node2D, item_type: int, amount: int)

# 物品注册到追踪系统
signal item_registered(item: Node2D)

# 物品从追踪系统移除
signal item_unregistered(item: Node2D)
```

### 村民类事件
```gdscript
# 村民空闲（任务完成后）
signal villager_idle(villager: Node2D)

# 村民任务被分配
signal villager_task_assigned(villager: Node2D, task_type: String, target: Node2D)

# 村民任务完成
signal villager_task_completed(villager: Node2D)
```

### 仓库类事件
```gdscript
# 仓库创建（第一次划定）
signal stockpile_created

# 仓库格子更新
signal stockpile_updated
```

### 季节类事件 [未来]
```gdscript
signal season_changed(season: int)  # 0=春, 1=夏, 2=秋, 3=冬
signal day_changed(day: int)
```

### UI类事件
```gdscript
# 提示消息
signal alert_message(message: String)
```

---

## 模块依赖关系

```
EventBus (无依赖)
    │
    ├── ResourceManager (依赖EventBus)
    │       │
    │       └── 订阅: item_stored → 更新资源统计 → 发布: resources_updated
    │
    ├── StockpileManager (依赖EventBus)
    │       │
    │       ├── 订阅: villager_idle → 自动分配搬运任务
    │       └── 发布: stockpile_created, stockpile_updated
    │
    ├── ItemManager (依赖EventBus)
    │       │
    │       ├── 订阅: item_dropped → 注册物品
    │       └── 发布: item_registered, item_unregistered
    │
    ├── Villager (依赖EventBus, ItemManager, StockpileManager)
    │       │
    │       ├── 订阅: stockpile_updated → 重新分配任务
    │       ├── 发布: villager_idle, villager_task_assigned, villager_task_completed
    │       └── 调用: ItemManager, StockpileManager的方法
    │
    └── UI (依赖EventBus, ResourceManager)
            │
            ├── 订阅: resources_updated, stockpile_created, alert_message
            └── 发布: 无（纯展示）
```

---

## 文件结构

### scripts/ 结构
```
scripts/
├── core/
│   └── EventBus.gd              # 事件总线（自动加载）
├── managers/
│   ├── ResourceManager.gd        # 资源管理
│   ├── StockpileManager.gd       # 仓库管理
│   ├── ItemManager.gd            # 物品追踪
│   ├── SeasonManager.gd          # 季节系统 [未来]
│   ├── CropManager.gd           # 作物管理 [未来]
│   └── BuildingManager.gd        # 建筑管理 [未来]
├── entities/
│   ├── Villager.gd              # 村民
│   ├── ResourceNode.gd          # 资源节点
│   ├── ItemDrop.gd              # 物品掉落
│   └── Animal.gd                # 动物AI
├── world/
│   ├── Map.gd                   # 地图生成+寻路
│   └── CameraController.gd      # 相机控制
├── ui/
│   ├── Node2D.gd                # 主UI逻辑
│   └── map_data.gd              # 地图配置
└── scenes/
    ├── Menu.tscn                 # 菜单场景
    ├── MapData.tscn             # 地图配置界面
    ├── Map_generate.tscn        # 游戏地图场景
    └── ItemDrop.tscn            # 物品掉落场景
```

### 场景文件
```
scenes/
├── Menu.tscn              # 菜单场景
├── MapData.tscn           # 地图配置界面
├── Map_generate.tscn      # 游戏地图场景（主场景）
└── ItemDrop.tscn          # 物品掉落场景
```

---

## 实施步骤

### 阶段一：核心基础设施
1. 创建 `EventBus.gd` - 定义所有事件信号
2. 创建 `ResourceManager.gd` - 资源统计
3. 创建 `ItemManager.gd` - 物品追踪
4. 创建 `StockpileManager.gd` - 仓库管理
5. 更新 `project.godot` - 配置多个自动加载

### 阶段二：地图系统
6. 创建 `Map.gd` - 寻路+地形生成
7. 创建 `Map_generate.tscn` - TileMap场景
8. 创建 `map_data.gd` + `MapData.tscn` - 配置界面

### 阶段三：实体系统
9. 创建 `Villager.gd` - 村民行为（任务状态机）
10. 更新 `ResourceNode.gd` - 适配新架构
11. 创建 `ItemDrop.gd` + `scenes/ItemDrop.tscn` - 物品掉落
12. 创建 `Animal.gd` - 动物AI

### 阶段四：游戏主控
13. 创建 `Node2D.gd` - UI+输入+教程
14. 创建 `CameraController.gd` - 相机控制
15. 更新 `Menu.tscn` - 菜单场景

### 阶段五：未来扩展接口（可选）
16. 创建 `SeasonManager.gd` - 季节系统框架
17. 创建 `CropManager.gd` - 作物系统框架
18. 创建 `BuildingManager.gd` - 建筑系统框架

### 阶段六：清理
19. 删除冗余文件
20. 测试完整流程

---

## 团队开发分工建议

### 开发者A - 核心系统
- EventBus
- ResourceManager
- ItemManager
- StockpileManager

### 开发者B - 实体系统
- Villager
- ResourceNode
- ItemDrop
- Animal

### 开发者C - 世界系统
- Map (地图生成+寻路)
- CameraController
- 地图配置界面

### 开发者D - UI系统
- Node2D (主UI)
- Menu.tscn
- 教程系统

### 开发者E - 扩展功能 [未来]
- SeasonManager
- CropManager
- BuildingManager

---

## 技术要点

### Manager基类设计（可选）
```gdscript
class_name BaseManager
extends Node

var event_bus: Node

func _ready() -> void:
    event_bus = get_node("/root/EventBus")

# 子类重写此方法返回需要连接的事件
func get_subscribed_events() -> Array:
    return []

# 子类重写此方法处理事件
func _on_event(event_name: String, args: Array) -> void:
    pass
```

### 信号连接辅助
```gdscript
func connect_event(signal_name: String, callable: Callable) -> void:
    if event_bus.has_signal(signal_name):
        event_bus.get(signal_name).connect(callable)
```

### 资源类型定义
```gdscript
# 所有模块共享的常量
const ResourceType = {
    WOOD = 0,
    STONE = 1,
    MEAT = 2
}

const SeasonType = {
    SPRING = 0,
    SUMMER = 1,
    AUTUMN = 2,
    WINTER = 3
}
```

---

## 工作量估计
- 阶段一（核心）：2-3小时
- 阶段二（地图）：2-3小时
- 阶段三（实体）：3-4小时
- 阶段四（UI）：2-3小时
- 阶段五（扩展）：可选
- 阶段六（清理）：1小时
- **总计：约10-14小时（不含扩展）**

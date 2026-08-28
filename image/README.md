# 卡片配图

把图片按下面的文件名放进本目录，对应的机器人消息就会自动带图；**没放就还是纯文本**，不用改代码。

支持扩展名：`.png` / `.jpg` / `.jpeg` / `.webp`（按此顺序取第一个命中的）。

## 文件名对照

| 文件名 | 出现在哪 | 触发方式 |
| --- | --- | --- |
| `jfsc.*` | 积分商城 | 群内 `/shop`、`/mall`、发「商城」 |
| `jf.*` | 我的积分账户 | 群内 `/jf`、发「积分」 |
| `jfph.*` | 积分排行榜 | 群内 `/jfph`、`/rank`、发「积分排行榜」 |
| `dh.*` | 积分兑换邀请券 | 群内 `/dh`、`/exchange` |
| `daoju.*` | 我的道具 | 群内 `/wddj`、`/buffs`、发「我的道具」 |
| `buff.*` | 属性面板 | 群内 `/mybuff`、`/buff`、发「我的buff」 |
| `ads.*` | 反垃圾主菜单 | 群内 `/ads`、`/antispam` |
| `console.*` | 订阅控制台登录 | 私聊 `/console` |

## 两条硬限制（决定了图什么时候会被忽略）

1. **文案超过 caption 上限就不带图。** Telegram 图片说明上限 1024 字符，代码里留余量按 960 判断。
   所以内容长的面板（如翻到很多条的积分流水）会自动退回纯文本——这是正常行为，不是 bug。
2. **带图的消息不能改文案，只能改图片说明。** 翻页/切菜单已做兼容：
   放得下就改 caption，放不下就删图重发为纯文本消息。

## 建议规格

- 尺寸 1024×512 左右的横图（Telegram 里显示为宽幅卡片，不会顶掉太多聊天区）
- 单文件控制在 200KB 以内，群里加载快
- 主体信息靠左/居中，**别把关键文字放在最下方**——下面紧挨着就是文案和按钮

## 出图提示词（扁平简约风，可直接用）

通用前缀：

```
flat vector illustration, minimal, clean geometric shapes, soft gradient background,
no text, no letters, centered composition, generous negative space,
muted modern palette, 2:1 wide banner, crisp edges, no photorealism, no 3D render
```

各张的主体词（接在前缀后面）：

| 文件 | 主体提示词 | 建议主色 |
| --- | --- | --- |
| `jfsc` | `a simple shopping bag and a gift box beside stacked coins` | 暖金 + 米白 |
| `jf` | `a single large coin with a star, small ascending bar chart behind` | 金黄 + 深蓝 |
| `jfph` | `a three-step podium with a trophy on the tallest step` | 橙金 + 靛蓝 |
| `dh` | `a ticket stub with a coin turning into it, exchange arrows` | 青绿 + 奶白 |
| `daoju` | `a backpack with a sword, shield and potion bottle icons around it` | 棕橙 + 灰蓝 |
| `buff` | `a glowing hexagonal stat panel with upward arrows and a shield` | 紫罗兰 + 青 |
| `ads` | `a shield deflecting paper-plane spam messages, checkmark inside` | 蓝 + 白 |
| `console` | `a laptop screen with sliders and toggles, small key icon` | 深灰蓝 + 亮青 |

提示词里写了 `no text` 是刻意的：中文字在生图模型里几乎必糊，标题由消息文案本身承担，图只做氛围。

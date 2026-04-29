# tg-antispam

一键安装
```bash
bash <(curl -Ls https://raw.githubusercontent.com/ryty1/tg-antispam/refs/heads/main/install.sh)
```
# 安装变量说明
- 机器人TOKEN令牌 `（必填）`
- 你的 Chat ID `（必填）`
- [授权服务器地址](https://t.me/kadssvip_bot) `（必填）`
- [授权码](https://t.me/kadssvip_bot) `（必填）`
  ```
  授权服务器地址 和 授权码 在 平台机器人【KADSS】
  
  发送 `/console` 登录后台授权中心。
  ```
- 机器人 `/console` 管理后台是否使用 HTTPS 域名（y/N） `（选填）`
  - N：自动生成 http://IP:8787 (Polling 模式)
  - y：你输入 https://你的域名  (Webhook 模式) 推荐，需要提前进行域名解析！

- 是否自定义 AI 接口（y/N） `（选填）`
  - N：AI接口 1/2/3 默认留空，也可以在 `/console` 中后续设置！
  - y：手动输入 AI接口1（必填），AI接口 2/3（可选）
  ```
  格式： 接口|key|模型|模式
   https://openai.com/v1|sk-xxxxxxxxxxxx|gpt-5.4-mini|chat
  ```
- 如果选 HTTPS，还会额外问：
  - 证书通知邮箱（用于 Certbot 申请证书）

# 部署效果
- 获得与 [KADSS](https://t.me/kadssvip_bot),一模一样的效果，允许授权用户自己管理自己的订阅用户。
- 支持多种种支付接口。
- 对接魔方财务，实现TG群组积分兑换续期码/优惠码，平台绑定TG，在群守护功能。（需配合我的魔方插件）
- 其他功能在 [体验群组](https://t.me/vitebits) 中功能体验！
- 支持TG更新推送及更新！

# Commands 菜单快捷模版
```
console - 订阅控制台
ads - UI主面板
ban - 封禁或举报
unban - 解封目标
jy - 禁言可带时长
unjy - 解除禁言
cj - 发起抽奖
dc - 查询DC数据中心
id - 查询用户信息
jf - 查询本人积分
dh - 兑换邀请码
shop - 积分商城
yq - 查看邀请券
importset - 积分覆盖
importadd - 积分追加
wladd - 添加白名单
wlrm - 移除白名单
safe - 标记正常样本
ww - 创建狼人杀大厅
wd - 谁是卧底大厅
rr - 俄罗斯轮盘大厅
dd - 决斗
21 - 21点
nn - 牛牛斗牛
```

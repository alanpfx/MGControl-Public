# 如何确认本车 iBeacon 参数

iBeacon UUID、Major、Minor来自设备实际广播，不是VIN、系统配对码或CoreBluetooth设备UUID。官方App包含iBeacon方法名只能说明SDK有此能力，不能证明每辆车都广播。

1. 使用安卓手机上的Nordic nRF Connect for Mobile，打开Scanner扫描，给予扫描需要的蓝牙/附近设备/定位权限；不需要连接或配对。
2. 在车旁查看广播详情，寻找明确的iBeacon解析及Proximity UUID、Major、Minor。只有普通服务UUID或Manufacturer Data不能直接作为本车iBeacon参数。
3. 分别在锁车后未连接、官方App正常连接后再断开的状态记录；走远/靠近以及换停车位置复核，排除手机、其他车辆及附近商店的Beacon。RSSI强或名称相似仅是线索。
4. 若只显示原始Manufacturer Data，可提供遮住VIN/设备地址的截图协助解析；不提供PIN、token或钥匙材料。没有捕获不能直接认定车辆没有该能力。
5. 确认归属后在MGControl无感设置中输入完整UUID及十进制Major/Minor（0—65535），启用并保存；需要“始终允许”定位、系统后台App刷新。
6. 先做关闭/开启辅助的对照，分别记入区事件、蓝牙连接、车辆认证、实际解锁的时间。参数及唤醒未验证时保持关闭。Beacon只提供运行/连接机会，不能证明车门已锁，也不授权开关锁。

若只有iPhone，Core Location的区域监测需要先知道目标UUID；常规BLE扫描不能保证发现未知iBeacon。优先用安卓只读扫描，或从经验证的官方配置/车辆广播获取。不要填网上示例UUID。

参考：[Nordic工具](https://www.nordicsemi.com/Products/Development-tools/nRF-Connect-for-mobile)、[Apple iBeacon接近检测](https://developer.apple.com/documentation/corelocation/determining-the-proximity-to-an-ibeacon-device)。系统调度、权限、蓝牙、低电量及用户强退均可能影响效果，不保证立即唤醒。

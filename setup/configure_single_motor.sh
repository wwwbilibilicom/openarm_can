#!/usr/bin/env bash
set -e  # 遇错即停
can_normal_bdrate=1000000
can_fd_bdrate=5000000
export ROS_WS=/home/wenbo/lab_dev/openarm/ws_safearm/

printf '\e[8;25;100t'
printf "\033[1;95;100m"
cat << "EOF"
                                                                                                    
                                 __    __   ______   ________   ______                            
                                /  |  /  | /      \ /        | /      \                             
                                $$ |  $$ |/$$$$$$  |$$$$$$$$/ /$$$$$$  |                           
                                $$ |  $$ |$$ \__$$/    $$ |   $$ |  $$/                             
                                $$ |  $$ |$$      \    $$ |   $$ |                                 
                                $$ |  $$ | $$$$$$  |   $$ |   $$ |   __                            
                                $$ \__$$ |/  \__$$ |   $$ |   $$ \__/  |                           
                                $$    $$/ $$    $$/    $$ |   $$    $$/                            
                                 $$$$$$/   $$$$$$/     $$/     $$$$$$/                            
							
EOF
printf "\033[0m"
echo 
echo -e "\e[93mThis shell script is used to configure a single motor's CAN bus settings.\e[0m"

# 第一次确认
while true; do
    read -p "Did you get it? (y/n) " choice
    case "$choice" in
        y|Y)
            break
            ;;
        n|N)
            echo "本脚本未结束can总线，如需结束请自行关闭。"
            exit 0
            ;;
        *)
            echo "无效的输入，请按 y 继续或按 n 结束。"
            ;;
    esac
done

# 让用户输入要配置的电机ID
while true; do
    read -p "请输入要配置的电机ID（1-8）： " MOTOR_ID
    if [[ "$MOTOR_ID" =~ ^[1-8]$ ]]; then
        break
    else
        echo "无效的输入，请输入1-8之间的数字。"
    fi
done

# 计算对应的recv_can_id（send_can_id + 16）
RECV_CAN_ID=$((MOTOR_ID + 16))

# 让用户选择要配置的 CAN 接口，默认 can0
read -p "请输入要配置的 CAN 接口名称（默认 can0，如 can0/can1）： " CAN_IF
CAN_IF=${CAN_IF:-can0}
echo -e "\e[34m将要配置的电机ID为：$MOTOR_ID，接收CAN ID为：$RECV_CAN_ID，接口为：$CAN_IF\e[0m"

############################
# 1. 配置 CAN 2.0 普通波特率
############################
sudo ip link set "$CAN_IF" down
sleep 0.01
sudo ip link set "$CAN_IF" type can bitrate "$can_normal_bdrate"
sudo ip link set "$CAN_IF" up

echo -e "\e[34m标准 CAN 通信开始，接口：$CAN_IF，波特率为：\e[0m"
echo "$can_normal_bdrate"

cd "$ROS_WS/src/openarm_can"
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
sudo cmake --install build

cd "$ROS_WS/src/openarm_can/setup"

# 只对指定的电机ID设置普通 CAN 波特率
echo -e "\e[34m正在为电机ID $MOTOR_ID 设置标准CAN波特率...\e[0m"
python3 change_baudrate.py --baudrate "$can_normal_bdrate" --canid "$MOTOR_ID" --socketcan "$CAN_IF"
sleep 0.01

echo -e "\e[34m电机ID $MOTOR_ID 标准 CAN 频率设置成功，当前波特率为：\e[0m"
echo "$can_normal_bdrate"

#################################
# 2. 在 motor-check 之前加入归零确认
#################################

echo -e "\e[93m是否需要现在执行归零？（推荐在 motor-check 前执行）\e[0m"
echo -e "\e[93m将会运行： ./set_zero.sh $CAN_IF $(printf "%03d" "$MOTOR_ID")\e[0m"

while true; do
    read -p "是否执行归零？(y/n): " zero_choice
    case "$zero_choice" in
        y|Y)
            echo -e "\e[34m正在执行归零： ./set_zero.sh $CAN_IF $(printf "%03d" "$MOTOR_ID")\e[0m"
            # 进入 openarm_can/setup 目录
            cd "$ROS_WS/src/openarm_can/setup"
            ./set_zero.sh "$CAN_IF" "$(printf "%03d" "$MOTOR_ID")"
            echo -e "\e[32m归零完成！\e[0m"
            break
            ;;
        n|N)
            echo -e "\e[33m跳过归零，继续执行 motor-check。\e[0m"
            break
            ;;
        *)
            echo "无效的输入，请按 y 或 n。"
            ;;
    esac
done



############################
# 3. motor-check 检查
############################
cd "$ROS_WS/src/openarm_can/build"
echo -e "\e[34m开始检查电机ID $MOTOR_ID 的参数、零点、can_ID、can_master（接口：$CAN_IF）\e[0m"
echo -e "\e[34m发送CAN ID: $MOTOR_ID，接收CAN ID: $RECV_CAN_ID\e[0m"

# 只检查指定的电机
./motor-check "$MOTOR_ID" "$RECV_CAN_ID" "$CAN_IF"

echo -e "\e[93m请检查电机ID $MOTOR_ID 是否在 0 位，若不是请运行 openarm 官方例程进行归 0 后继续！！！\e[0m"

#################################
# 4. 询问是否切到 CAN FD 模式
#################################
while true; do
    read -p "按 y 继续配置为 CAN FD（接口：$CAN_IF，电机ID：$MOTOR_ID），按 n 结束: " choice
    case "$choice" in
        y|Y)
            echo "继续执行脚本，配置 CAN FD..."
            cd "$ROS_WS/src/openarm_can/setup"

            # 先让电机内部波特率改为 FD 对应速率
            echo -e "\e[34m正在为电机ID $MOTOR_ID 设置CAN FD内部波特率...\e[0m"
            python3 change_baudrate.py --baudrate "$can_fd_bdrate" --canid "$MOTOR_ID" --socketcan "$CAN_IF"
            sleep 0.01
            echo -e "\e[34m电机ID $MOTOR_ID CAN FD 内部频率设置成功，当前波特率为：\e[0m"
            echo "$can_fd_bdrate"

            # 再把系统 CAN 接口切到 FD 模式
            sudo ip link set "$CAN_IF" down
            sleep 0.01
            sudo ip link set "$CAN_IF" type can bitrate "$can_normal_bdrate" dbitrate "$can_fd_bdrate" fd on
            sleep 0.01
            sudo ip link set "$CAN_IF" up

            echo -e "\e[34mCAN FD 通信开始，接口：$CAN_IF，数据段波特率为：\e[0m"
            echo "$can_fd_bdrate"
            echo -e "\e[34m电机ID $MOTOR_ID 配置完成（接口：$CAN_IF）\e[0m"

            echo "恭喜你，开心快乐地玩耍机械臂吧！"
            exit 0
            ;;
        n|N)
            echo "已完成标准 CAN 配置（接口：$CAN_IF，电机ID：$MOTOR_ID）。本脚本未结束 CAN 总线，如需结束请自行关闭。"
            echo "恭喜你，开心快乐地玩耍机械臂吧！"
            exit 0
            ;;
        *)
            echo "无效的输入，请按 y 继续或按 n 结束。"
            ;;
    esac
done


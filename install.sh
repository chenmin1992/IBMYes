#!/bin/bash
SH_PATH=$(cd "$(dirname "$0")";pwd)
cd ${SH_PATH}

create_mainfest_file(){
    cd ${SH_PATH}/IBMYes/v2ray-cloudfoundry
    echo "进行配置..."
    read -p "请输入你的应用名称: " IBM_APP_NAME
    if [ -z "${IBM_APP_NAME}" ]; then
        echo '未填写应用名称, 退出'
        exit 1
    fi
    echo "应用名称: ${IBM_APP_NAME}"
    echo "正在获取内存大小..."
    IBM_MEM_SIZE=$(ibmcloud cf app ${IBM_APP_NAME} | grep 'memory usage' | awk '{print $3}')
    if [ -z "${IBM_MEM_SIZE}" ]; then
        IBM_MEM_SIZE="64M"
        echo "找不到应用 ${IBM_APP_NAME}, 已设置应用内存为 64M, 搭建完可以在控制台调整"
    fi
    echo "内存大小: ${IBM_MEM_SIZE}"
    V2RAY_UUID=$(cat /proc/sys/kernel/random/uuid)
    V2RAY_WS_PATH=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 6)

    cat > manifest.yml <<EOF
applications:
- path: .
  name: ${IBM_APP_NAME}
  random-route: false
  memory: ${IBM_MEM_SIZE}
EOF

    cat > v2ray/config.json <<EOF
{
  "inbounds":[
    {
      "port":8080,
      "protocol":"vmess",
      "settings":{
        "clients":[
          {
            "id":"${V2RAY_UUID}",
            "alterId":4
          }
        ]
      },
      "streamSettings":{
        "network":"ws",
        "wsSettings":{
          "path":"${V2RAY_WS_PATH}"
        }
      }
    }
  ],
  "outbounds":[
    {
      "protocol":"freedom",
      "settings":{

      }
    }
  ]
}
EOF
    echo "配置完成."
}

clone_repo(){
    echo "进行初始化..."
    rm -rf IBMYes
    git clone https://github.com/chenmin1992/IBMYes
    cd IBMYes/v2ray-cloudfoundry/v2ray
    rm -f v2ray v2ctl geoip.dat geosite.dat >/dev/null 2>&1
    DOWNLOAD_LINK="$(curl -sfL https://api.github.com/repos/v2fly/v2ray-core/releases/latest | grep linux-64 | grep browser_download_url | head -1 | awk -F'"' '{print $4}')"
    if ! curl -LH 'Cache-Control: no-cache' -o "latest-v2ray.zip" "$DOWNLOAD_LINK"; then
        echo 'error: 下载V2Ray失败，请重试'
        exit 1
    fi
    unzip latest-v2ray.zip v2ray v2ctl geoip.dat geosite.dat
    rm latest-v2ray.zip
    chmod 0755 v2ray v2ctl
    ibmcloud cf install -f -v 6.51.0
    ibmcloud target --cf
    echo "初始化完成."
}

install(){
    echo "进行安装..."
    cd ${SH_PATH}/IBMYes/v2ray-cloudfoundry
    ibmcloud cf push
    IBM_APP_ADDR=$(ibmcloud cf app ${IBM_APP_NAME} | grep routes | awk '{print $2}')
    if [ -z "${IBM_APP_ADDR}" ]; then
        ibmcloud cf map-route "${IBM_APP_NAME}" mybluemix.net --hostname "${IBM_APP_NAME}"
        IBM_APP_ADDR='${IBM_APP_NAME}.mybluemix.net'
    fi

    echo "安装完成."
    echo "地址:          ${IBM_APP_ADDR}"
    echo "V2RAY_UUID:          ${V2RAY_UUID}"
    echo "WebSocket路径: ${V2RAY_WS_PATH}"
    VMESSCODE=$(base64 -w 0 <<EOF
{
  "v": "2",
  "ps": "IBMYes",
  "add": "${IBM_APP_ADDR}",
  "port": "443",
  "id": "${V2RAY_UUID}",
  "aid": "4",
  "net": "ws",
  "type": "none",
  "host": "",
  "path": "${V2RAY_WS_PATH}",
  "tls": "tls"
}
EOF
    )
	echo "直连配置: "
    echo "vmess://${VMESSCODE}"
    echo "Clash直连配置: "
    cat <<EOF
- name: IBMYes
  type: vmess
  server: ${IBM_APP_ADDR}
  port: 443
  uuid: ${V2RAY_UUID}
  alterId: 4
  cipher: auto
  udp: true
  tls: true
  skip-cert-verify: false
  network: ws
  ws-path: ${V2RAY_WS_PATH}
EOF

    read -p '请输入Cloudflare worker的地址: ' CF_WORKER_ADDR
    [ -z "${CF_WORKER_ADDR}" ] && exit 0
    VMESSCODE=$(base64 -w 0 <<EOF
{
  "v": "2",
  "ps": "IBMYes",
  "add": "cloudflare.com",
  "port": "443",
  "id": "${V2RAY_UUID}",
  "aid": "4",
  "net": "ws",
  "type": "none",
  "host": "${CF_WORKER_ADDR}",
  "path": "${V2RAY_WS_PATH}",
  "tls": "tls"
}
EOF
    )
    echo "加速配置: "
    echo "vmess://${VMESSCODE}"
    echo "Clash加速配置: "
    cat <<EOF
- name: IBMYes
  type: vmess
  server: cloudflare.com
  port: 443
  uuid: ${V2RAY_UUID}
  alterId: 4
  cipher: auto
  udp: true
  tls: true
  skip-cert-verify: false
  network: ws
  ws-path: ${V2RAY_WS_PATH}
  ws-headers:
    Host: ${CF_WORKER_ADDR}
EOF
}

clone_repo
create_mainfest_file
install
exit 0
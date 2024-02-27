#!/bin/bash

#Frigate:https://github.com/blakeblackshear/frigate
echo "Updating Frigate."

SERVICE="frigate go2rtc nginx"
sudo systemctl stop $SERVICE

sudo apt update
sudo apt upgrade -y

sudo python3 -m pip install --upgrade pip

######UPDATE GO2RTC
sudo mkdir -p /usr/local/go2rtc/bin
cd /usr/local/go2rtc/bin
#Get latest release
sudo wget -O go2rtc "https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_amd64"
chmod +x go2rtc


#####UPDATE FFMPEG (BTBN)
##Need xz utils to untar
#sudo apt install xz-utils
#sudo mkdir -p /usr/lib/btbn-ffmpeg
#sudo wget -qO btbn-ffmpeg.tar.xz "https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-n6.1-latest-linux64-gpl-6.1.tar.xz "
#sudo tar -xf btbn-ffmpeg.tar.xz -C /usr/lib/btbn-ffmpeg --strip-components 1
#sudo rm -rf btbn-ffmpeg.tar.xz /usr/lib/btbn-ffmpeg/doc /usr/lib/btbn-ffmpeg/bin/ffplay


######UPDATE NODEJS
#curl -fsSL https://deb.nodesource.com/setup_21.x | sudo -E bash -
#sudo apt-get install -y nodejs


########UPDATE FRIGATE
cd /opt

#Get latest release
version=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/blakeblackshear/frigate/releases/latest)
version=${version##*/}

sudo wget https://github.com/blakeblackshear/frigate/archive/refs/tags/${version}.tar.gz -O frigate.tar.gz
#mkdir frigate
sudo tar -xzf frigate.tar.gz -C frigate --strip-components 1 --overwrite

#Cleanup
sudo rm frigate.tar.gz

cd /opt/frigate
sudo docker/main/build_nginx.sh


#Cleanup previous wheels
sudo rm -rf /wheels

sudo pip3 install -r docker/main/requirements.txt
sudo pip3 wheel --wheel-dir=/wheels -r /opt/frigate/docker/main/requirements-wheels.txt

sudo pip3 install -U /wheels/*.whl
sudo ldconfig
sudo pip3 install -U /wheels/*.whl

sudo pip3 install -r /opt/frigate/docker/main/requirements-dev.txt

#cd /opt/frigate

### Starting Frigate
#First, comment the call to S6 in the run script
sudo sed -i '/^s6-svc -O \.$/s/^/#/' /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run

## Call nginx from absolute path
## nginx --> /usr/local/nginx/sbin/nginx
sudo sed -i 's/exec nginx/exec \/usr\/local\/nginx\/sbin\/nginx/g' /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run

#Copy preconfigured files
sudo cp -a /opt/frigate/docker/main/rootfs/. /

#Can't log to /dev/stdout with systemd, so log to file
sudo sed -i 's/error_log \/dev\/stdout warn\;/error_log nginx\.err warn\;/' /usr/local/nginx/conf/nginx.conf
sudo sed -i 's/access_log \/dev\/stdout main\;/access_log nginx\.log main\;/' /usr/local/nginx/conf/nginx.conf


# Frigate web build
cd /opt/frigate/web

sudo npm install
sudo npm run build

sudo cp -r dist/BASE_PATH/monacoeditorwork/* dist/assets/
cd /opt/frigate/
sudo cp -r /opt/frigate/web/dist/* /opt/frigate/web/

sudo systemctl start $SERVICE

echo "Done."
#!/bin/bash
#Script to setup Frigate in Proxmox LXC, on a Debian 11 standard image
#LXC config: Debian 11, 20Gb disk (40Gb with TensorRT), 4 cores, 4Gb memory
#Make sure the LXC is already set up with Nvidia drivers (and appropriate rights to the gpu)
#Test with command: nvidia-smi
#It should show a table with the GPU
#Tutorial to setup GPU passthrough to LXC: https://passbe.com/2020/02/19/gpu-nvidia-passthrough-on-proxmox-lxc-container/
#For reference, I needed to append this in my LXC config:
#lxc.cgroup2.devices.allow: c 195:* rwm
#lxc.cgroup2.devices.allow: c 507:* rwm
#lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
#lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
#lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
#lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
#lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file

#Command to launch script:
#wget -O- https://raw.githubusercontent.com/remz1337/frigate/dev/standalone_install.sh | bash -

#Flag to deploy Frigate with TensorRT, assuming Nvidia GPU with dependencies already installed. 0=disabled (default), 1=enabled
USE_TENSORRT=0

echo "Installing Frigate stack (v0.13.0-beta2)"

#Run everything as root
#sudo su
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

#Configuration to make unattended installs with APT
#https://serverfault.com/questions/48724/100-non-interactive-debian-dist-upgrade
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
#especially libc6, installed part of the dependency script (install_deps.sh)
echo 'libc6 libraries/restart-without-asking boolean true' | debconf-set-selections

cd /opt

apt update
apt upgrade -y
#I tried to install all the dependencies at the beginning, but it induced an error when building nginx, so I kept them in the same order of the Dockerfile
apt install -y git automake build-essential wget xz-utils

#Pull Frigate from  repo
#git clone https://github.com/blakeblackshear/frigate.git
wget https://github.com/blakeblackshear/frigate/archive/refs/tags/v0.13.0-beta2.tar.gz -O frigate.tar.gz
mkdir frigate
tar -xzf frigate.tar.gz -C frigate --strip-components 1

cd /opt/frigate

#Used in build dependencies scripts
export TARGETARCH=amd64

docker/main/build_nginx.sh


mkdir -p /usr/local/go2rtc/bin
cd /usr/local/go2rtc/bin

wget -O go2rtc "https://github.com/AlexxIT/go2rtc/releases/download/v1.8.1/go2rtc_linux_${TARGETARCH}"
chmod +x go2rtc

cd /opt/frigate

### OpenVino
apt install -y wget python3 python3-distutils
wget https://bootstrap.pypa.io/get-pip.py -O get-pip.py
python3 get-pip.py "pip"
pip install -r docker/main/requirements-ov.txt


# Get OpenVino Model
mkdir -p /opt/frigate/models
cd /opt/frigate/models && omz_downloader --name ssdlite_mobilenet_v2
cd /opt/frigate/models && omz_converter --name ssdlite_mobilenet_v2 --precision FP16

# Build libUSB without udev.  Needed for Openvino NCS2 support
cd /opt/frigate

export CCACHE_DIR=/root/.ccache
export CCACHE_MAXSIZE=2G

apt install -y unzip build-essential automake libtool ccache pkg-config

wget https://github.com/libusb/libusb/archive/v1.0.26.zip -O v1.0.26.zip
unzip v1.0.26.zip
cd libusb-1.0.26
./bootstrap.sh
./configure --disable-udev --enable-shared
make -j $(nproc --all)

apt install -y --no-install-recommends libusb-1.0-0-dev

cd /opt/frigate/libusb-1.0.26/libusb

mkdir -p /usr/local/lib
/bin/bash ../libtool  --mode=install /usr/bin/install -c libusb-1.0.la '/usr/local/lib'
mkdir -p /usr/local/include/libusb-1.0
/usr/bin/install -c -m 644 libusb.h '/usr/local/include/libusb-1.0'
mkdir -p /usr/local/lib/pkgconfig
cd /opt/frigate/libusb-1.0.26/
/usr/bin/install -c -m 644 libusb-1.0.pc '/usr/local/lib/pkgconfig'
ldconfig

######## Frigate expects model files at root of filesystem
#cd /opt/frigate/models
cd /

# Get model and labels
wget -O edgetpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess_edgetpu.tflite
wget -O cpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess.tflite

#cp /opt/frigate/labelmap.txt .
cp /opt/frigate/labelmap.txt /labelmap.txt
cp -r /opt/frigate/models/public/ssdlite_mobilenet_v2/FP16 openvino-model

wget https://github.com/openvinotoolkit/open_model_zoo/raw/master/data/dataset_classes/coco_91cl_bkgr.txt -O openvino-model/coco_91cl_bkgr.txt
sed -i 's/truck/car/g' openvino-model/coco_91cl_bkgr.txt
# Get Audio Model and labels
wget -qO cpu_audio_model.tflite https://tfhub.dev/google/lite-model/yamnet/classification/tflite/1?lite-format=tflite
cp /opt/frigate/audio-labelmap.txt /audio-labelmap.txt


# opencv & scipy dependencies
cd /opt/frigate

apt install -y python3 python3-dev wget build-essential cmake git pkg-config libgtk-3-dev libavcodec-dev libavformat-dev libswscale-dev libv4l-dev libxvidcore-dev libx264-dev libjpeg-dev libpng-dev libtiff-dev gfortran openexr libatlas-base-dev libssl-dev libtbb2 libtbb-dev libdc1394-22-dev libopenexr-dev libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev gcc gfortran libopenblas-dev liblapack-dev

pip3 install -r docker/main/requirements.txt

pip3 wheel --wheel-dir=/wheels -r /opt/frigate/docker/main/requirements-wheels.txt
#pip3 wheel --wheel-dir=/trt-wheels -r /opt/frigate/docker/tensorrt/requirements-amd64.txt

#Copy preconfigured files
cp -a /opt/frigate/docker/main/rootfs/. /

#exports are lost upon system reboot...
#export PATH="$PATH:/usr/lib/btbn-ffmpeg/bin:/usr/local/go2rtc/bin:/usr/local/nginx/sbin"

# Install dependencies
/opt/frigate/docker/main/install_deps.sh

#Create symbolic links to ffmpeg and go2rtc
ln -svf /usr/lib/btbn-ffmpeg/bin/ffmpeg /usr/local/bin/ffmpeg
ln -svf /usr/lib/btbn-ffmpeg/bin/ffprobe /usr/local/bin/ffprobe
ln -svf /usr/local/go2rtc/bin/go2rtc /usr/local/bin/go2rtc

pip3 install -U /wheels/*.whl
ldconfig

# Install Node 16
#wget -O- https://deb.nodesource.com/setup_16.x | bash -

# Install Node 21
#curl -fsSL https://deb.nodesource.com/setup_21.x | sudo -E bash -
#sudo apt-get install -y nodejs
curl -fsSL https://deb.nodesource.com/setup_21.x | bash -

apt install -y nodejs
#npm install -g npm@9
npm install -g npm

pip3 install -r /opt/frigate/docker/main/requirements-dev.txt

# Frigate web build
# This should be architecture agnostic, so speed up the build on multiarch by not using QEMU.
cd /opt/frigate/web

npm install

npm run build

cp -r dist/BASE_PATH/monacoeditorwork/* dist/assets/

cd /opt/frigate/

cp -r /opt/frigate/web/dist/* /opt/frigate/web/


if [[ "$USE_TENSORRT" == 1 ]]; then
################ BUILDING TENSORRT

pip3 wheel --wheel-dir=/trt-wheels -r /opt/frigate/docker/tensorrt/requirements-amd64.txt
pip3 install -U /trt-wheels/*.whl
#ln -s libnvrtc.so.11.2 /usr/local/lib/python3.9/dist-packages/nvidia/cuda_nvrtc/lib/libnvrtc.so
ldconfig

#pip3 install -U /trt-wheels/*.whl

cp -a /opt/frigate/docker/tensorrt/detector/rootfs/. /


echo "Depoloying Frigate detector models running on Nvidia GPU"
echo "Make sure CUDA, cuDNN and TensorRT are already installed (with updated LD_LIBRARY_PATH)"


### Install TensorRT detector (using Nvidia GPU)
# Avoid "LD_LIBRARY_PATH: unbound variable" by initializing the variable
#export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

################################# THIS IS OUTDATED, FRIGATE v0.13 HAS A S6 RUN SCRIPT TO BUILD TENSORRT DEMOS
#mkdir -p /tensorrt_models
#cd /tensorrt_models
#wget https://github.com/blakeblackshear/frigate/raw/master/docker/tensorrt_models.sh
#chmod +x tensorrt_models.sh
#######################################################################

mkdir -p /usr/local/src/tensorrt_demos
cd /usr/local/src


#### Need to adjust the tensorrt_demos files to replace TensorRT include path (it's hardcoded to v7 installed in /usr/local)
## /tensorrt_demos/plugins/Makefile --> change INCS and LIBS paths

######## MAKE SOME EDITS TO UPDATE TENSORRT PATHS
#Create script to fix hardcoded TensorRT paths
fix_tensorrt="$(cat << EOF
#!/bin/bash
sed -i 's/\/usr\/local\/TensorRT-7.1.3.4/\/tensorrt\/TensorRT-8.6.1.6/g' /usr/local/src/tensorrt_demos/plugins/Makefile
EOF
)"

#echo "${fix_tensorrt}" > /usr/local/src/tensorrt_demos/fix_tensorrt.sh
echo "${fix_tensorrt}" > /opt/frigate/fix_tensorrt.sh

#insert after this line :git clone --depth 1 https://github.com/yeahme49/tensorrt_demos.git /tensorrt_demos
#sed -i '18 i bash \/tensorrt_models\/fix_tensorrt.sh' tensorrt_models.sh
sed -i '9 i bash \/opt\/frigate\/fix_tensorrt.sh' /opt/frigate/docker/tensorrt/detector/tensorrt_libyolo.sh

#apt install python and g++
apt install -y python-is-python3 g++
/opt/frigate/docker/tensorrt/detector/tensorrt_libyolo.sh


### NEED TO BUILD THE TRT MODELS
cd /opt/frigate
export YOLO_MODELS="yolov4-tiny-288,yolov4-tiny-416,yolov7-tiny-416"
export TRT_VER=8.5.3
bash /opt/frigate/docker/tensorrt/detector/rootfs/etc/s6-overlay/s6-rc.d/trt-model-prepare/run

#End conditional block for TensorRT
fi




### BUILD COMPLETE, NOW INITIALIZE

mkdir /config
cp -r /opt/frigate/config/. /config
cp /config/config.yml.example /config/config.yml

################### EDIT CONFIG FILE HERE ################
#mqtt:
#  enabled: False
#
#cameras:
#  Camera1:
#    ffmpeg:
#      hwaccel_args: -c:v h264_cuvid
##      hwaccel_args: preset-nvidia-h264 #This one is not working...
#      inputs:
#        - path: rtsp://user:password@192.168.1.123:554/h264Preview_01_main
#          roles:
#            - detect
#    detect:
#      enabled: False
#      width: 2560
#      height: 1920
#########################################################

cd /opt/frigate

/opt/frigate/.devcontainer/initialize.sh

### POST_CREATE SCRIPT

############## Skip the ssh known hosts editing commands when running as root
######/opt/frigate/.devcontainer/post_create.sh

# Frigate normal container runs as root, so it have permission to create
# the folders. But the devcontainer runs as the host user, so we need to
# create the folders and give the host user permission to write to them.
#sudo mkdir -p /media/frigate
#sudo chown -R "$(id -u):$(id -g)" /media/frigate

make version

cd /opt/frigate/web

npm install

npm run build

cd /opt/frigate

#####Start order should be:
#1. Go2rtc
#2. Frigate
#3. Nginx

### Starting go2rtc
#Create systemd service. If done manually, edit the file (nano /etc/systemd/system/go2rtc.service) then copy/paste the service configuraiton
go2rtc_service="$(cat << EOF

[Unit]
Description=go2rtc service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStart=bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/go2rtc/run

[Install]
WantedBy=multi-user.target

EOF
)"

echo "${go2rtc_service}" > /etc/systemd/system/go2rtc.service

systemctl start go2rtc
systemctl enable go2rtc

#Allow for a small delay before starting the next service
sleep 3

#Test go2rtc access at
#http://<machine_ip>:1984/



### Starting Frigate
#First, comment the call to S6 in the run script
sed -i '/^s6-svc -O \.$/s/^/#/' /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run

#Second, install yq, needed by script to check database path
wget -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod a+x /usr/local/bin/yq

#Create systemd service
frigate_service="$(cat << EOF

[Unit]
Description=Frigate service
After=go2rtc.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStart=bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run

[Install]
WantedBy=multi-user.target

EOF
)"

echo "${frigate_service}" > /etc/systemd/system/frigate.service

systemctl start frigate
systemctl enable frigate

#Allow for a small delay before starting the next service
sleep 3

### Starting Nginx

## Call nginx from absolute path
## nginx --> /usr/local/nginx/sbin/nginx
sed -i 's/exec nginx/exec \/usr\/local\/nginx\/sbin\/nginx/g' /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run

#Can't log to /dev/stdout with systemd, so log to file
sed -i 's/error_log \/dev\/stdout warn\;/error_log nginx\.err warn\;/' /usr/local/nginx/conf/nginx.conf
sed -i 's/access_log \/dev\/stdout main\;/access_log nginx\.log main\;/' /usr/local/nginx/conf/nginx.conf

#Create systemd service
nginx_service="$(cat << EOF

[Unit]
Description=Nginx service
After=frigate.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStart=bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run

[Install]
WantedBy=multi-user.target

EOF
)"

echo "${nginx_service}" > /etc/systemd/system/nginx.service

systemctl start nginx
systemctl enable nginx


#Test frigate through Nginx access at
#http://<machine_ip>:5000/


######## FULL FRIGATE CONFIG EXAMPLE:
#https://docs.frigate.video/configuration/

echo "Don't forget to edit the Frigate config file (/config/config.yml) and reboot."
echo "Frigate standalone installation complete! You can access the web interface at http://<machine_ip>:5000"

#!/bin/bash
#Script to install Nvidia dependencies required to use Nvidia GPU for object detection



apt install build-essential software-properties-common

#Download CUDA (for Debian 11 runfile)
#https://developer.nvidia.com/cuda-downloads

wget https://developer.download.nvidia.com/compute/cuda/12.2.2/local_installers/cuda_12.2.2_535.104.05_linux.run

#Install CUDA (Uncheck Driver installation if already install, but make sure versions are compatible)
sh cuda_12.2.2_535.104.05_linux.run

#... Then compile tensortt with cuda to use model in frigate
#https://docs.frigate.video/configuration/detectors/#nvidia-tensorrt-detector







#INSTALL CUDNN
#Need to find the download link using the link redirect trace browser extension
wget -O cudnn-local-repo-debian11-8.9.5.29_1.0-1_amd64.deb 'https://developer.download.nvidia.com/compute/cudnn/secure/8.9.5/local_installers/12.x/cudnn-local-repo-debian11-8.9.5.29_1.0-1_amd64.deb?EnYNwTbHpTfjEcaFvZsaIvlwQWN8-eh-49I5QFdLLCpFrCewjyEIS6CbBS4vRA9o848okz9qT-94lGGLKAA6XbBX8kfWSjP9xumm8-bsuhAmtS-Y7vT3YTJzE7ceRLgfHh2ftUYON4YKSiMlM98TEyQthoRhpOUkeLCvCavHhUztU--X7N2xUdCxrEkkvcr7uE-A3dD1sCogP6DuCq44Qp7l&t=eyJscyI6ImdzZW8iLCJsc2QiOiJodHRwczovL3d3dy5nb29nbGUuY29tLyJ9'

dpkg -i cudnn-local-repo-debian11-8.9.5.29_1.0-1_amd64.deb
cp /var/cudnn-local-repo-debian11-8.9.5.29/cudnn-local-461E8853-keyring.gpg /usr/share/keyrings/

apt update

apt install libcudnn8=8.9.5.29-1+cuda12.2
apt install libcudnn8-dev=8.9.5.29-1+cuda12.2








####INSTALL TENSORRT
#https://docs.nvidia.com/deeplearning/tensorrt/install-guide/index.html#installing-tar
mkdir /tensorrt
cd /tensorrt

wget https://developer.nvidia.com/downloads/compute/machine-learning/tensorrt/secure/8.6.1/tars/TensorRT-8.6.1.6.Linux.x86_64-gnu.cuda-12.0.tar.gz

tar -xzvf TensorRT-8.6.1.6.Linux.x86_64-gnu.cuda-12.0.tar.gz

####### ADD THIS TO BASHRC
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/tensorrt/TensorRT-8.6.1.6/lib


cd /tensorrt/TensorRT-8.6.1.6/python
python3 -m pip install tensorrt-*-cp39-none-linux_x86_64.whl

cd ../uff
python3 -m pip install uff-0.6.9-py2.py3-none-any.whl

cd ../graphsurgeon
python3 -m pip install graphsurgeon-0.4.6-py2.py3-none-any.whl

cd ../onnx_graphsurgeon
python3 -m pip install onnx_graphsurgeon-0.3.12-py2.py3-none-any.whl



echo "Don't forget to edit your bashrc file (home/$USER/.bashrc OR nano /root/.bashrc) to add the following lines:
export CUDA_HOME=/usr/local/cuda
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:/usr/local/cuda-12.2/targets/x86_64-linux/lib:/tensorrt/TensorRT-8.6.1.6/lib
export PATH=$PATH:$CUDA_HOME/bin
"
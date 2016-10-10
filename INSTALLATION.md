## Installation Instructions

### Installing the Essential requirements
    sudo apt-get install -y git python-pip python-dev
    sudo apt-get install -y python-dev
    sudo apt-get install -y autoconf automake libtool curl make g++ unzip
    sudo apt-get install -y libgflags-dev libgoogle-glog-dev liblmdb-dev
    sudo apt-get install libprotobuf-dev libleveldb-dev libsnappy-dev libopencv-dev libhdf5-serial-dev protobuf-compiler

### Install Torch
    git clone https://github.com/torch/distro.git ~/torch --recursive
    cd ~/torch; bash install-deps;
    ./install.sh
    source ~/.bashrc

### Install PyTorch(Python Lua Wrapper)
    git clone https://github.com/hughperkins/pytorch.git
    cd pytorch
    source ~/torch/install/bin/torch-activate
    ./build.sh

### Install RabbitMQ and Redis Server
    sudo apt-get install -y redis-server rabbitmq-server
    sudo rabbitmq-plugins enable rabbitmq_management
    sudo service rabbitmq-server restart 
    sudo service redis-server restart

### Lua dependencies for training
    luarocks install loadcaffe
    luarocks install nn
    luarocks install nngraph 
    luarocks install image 
The below two dependencies are only required if you are going to use GPU

    luarocks install cudnn
    luarocks install cunn

### Cuda Installation

Note: CUDA and cuDNN is only required if you are going to use GPU

Download and install CUDA and cuDNN from [nvidia website](https://developer.nvidia.com/cuda-downloads) 

### Install dependencies
    git clone https://github.com/Cloud-CV/diverse-beam-search.git dbs
    cd dbs

If you only have CPU, then use the command `sh models/cpu_models.sh` to download the model otherwise for GPU, use this command `sh models/gpu_models.sh` 

    pip install -r requirements.txt

### Running the RabbitMQ workers and Development Server

Open 2 different terminal sessions and run the following commands:

    python worker.py
    python manage.py runserver

You are all set now. Visit http://127.0.0.1:8000 and you will have your demo running successfully.
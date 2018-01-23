# Dockerfile for OpenCV with CUDA C++, Python 2.7 / 3.6 development 
# Pulling CUDA-CUDNN image from nvidia
FROM nvidia/cuda:9.1-cudnn7-devel-ubuntu16.04
MAINTAINER Mathieu Lamarre <mathieu.lamarre@gmail.com>

# Basic toolchain 
RUN apt-get update && \
        apt-get install -y \
        build-essential \
        git \
        wget \
        unzip \
        yasm \
        pkg-config 
        
# Building a recent CMake to benefit from improvement in the CUDA workflow
ENV CMAKE_VERSION=3.10
ENV CMAKE_BUILD=2
RUN apt-get install -y libcurl4-openssl-dev zlib1g-dev
RUN mkdir ~/temp && cd ~/temp && wget https://cmake.org/files/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}.${CMAKE_BUILD}.tar.gz\
&& tar -xzvf cmake-${CMAKE_VERSION}.${CMAKE_BUILD}.tar.gz
RUN cd ~/temp/cmake-${CMAKE_VERSION}.${CMAKE_BUILD}/ && ./bootstrap --system-curl && make -j4 && make install
RUN cd ~/temp/cmake-${CMAKE_VERSION}.${CMAKE_BUILD}/ && make clean && cd ~ && rm -rf temp 

WORKDIR /

# Getting OpenCV dependencies available with apt
RUN apt-get install -y \
        libswscale-dev \
        libtbb2 \
        libtbb-dev \
        libjpeg-dev \
        libpng-dev \
        libtiff-dev \
        libjasper-dev \
        libavformat-dev \
        libpq-dev

# Using Miniconda to get Python 2.7.x and 3.6.y to get Numpy linked with Intel MKL for max performance
RUN echo 'export PATH=/opt/conda/bin:$PATH' > /etc/profile.d/conda.sh && \
    wget --quiet https://repo.continuum.io/miniconda/Miniconda3-4.3.31-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh

ENV PATH /opt/conda/bin:$PATH

# Create two conda env. just for the purpose of building 
RUN conda create -y -n ocvpy3 python=3.6.4 numpy=1.14.0 mkl-devel
RUN conda create -y -n ocvpy2 python=2.7.14 numpy=1.14.0 mkl-devel

# Recent version of Eigen C++
ENV EIGEN_VERSION="3.3.4"
RUN wget http://bitbucket.org/eigen/eigen/get/3.3.4.zip -O ~/eigen-${EIGEN_VERSION}.zip \
&& unzip ~/eigen-${EIGEN_VERSION}.zip

WORKDIR /

ENV OPENCV_VERSION="3.4.0"

# Fetching OpenCV and OpenCV contrib sources
RUN wget https://github.com/opencv/opencv/archive/${OPENCV_VERSION}.zip -O ~/opencv-${OPENCV_VERSION}.zip \
&& unzip ~/opencv-${OPENCV_VERSION}.zip \
&& wget https://github.com/opencv/opencv_contrib/archive/${OPENCV_VERSION}.zip -O ~/opencv_contrib-${OPENCV_VERSION}.zip && unzip ~/opencv_contrib-${OPENCV_VERSION}.zip

RUN apt-get install -y libhdf5-dev

# Generate the makefile with CMake - note that IPP is downloaded at generation time
# Important: currently only builds sm_61 cuda architectures which means 
# GTX 1080, GTX 1070, GTX 1060, GTX 1050, GTX 1030, Titan Xp, Tesla P40, Tesla P4 and better
RUN cd /opencv-${OPENCV_VERSION} && mkdir build && cd build && \
cmake .. -DBUILD_TIFF=ON \
-DBUILD_opencv_java=OFF \
-DWITH_CUDA=ON \
-DCUDA_ARCH_BIN:STRING="6.1" \
-DWITH_OPENGL=ON \
-DWITH_OPENCL=ON \
-DWITH_IPP=ON \
-DWITH_TBB=ON \
-DWITH_MKL=ON \
-DMKL_WITH_TBB=ON \
-DMKL_ROOT_DIR=/opt/conda/envs/ocvpy3 \
-DWITH_EIGEN=ON \
-DWITH_V4L=ON \
-DWITH_FFMPEG=ON \
-DBUILD_TESTS=OFF \
-DBUILD_PERF_TESTS=OFF \
-DZLIB_ROOT=/opt/conda/envs/ocvpy3 \
-DPYTHON2_EXECUTABLE=/opt/conda/envs/ocvpy2/bin/python \
-DPYTHON2_INCLUDE_DIR=$(/opt/conda/envs/ocvpy2/bin/python -c "from distutils.sysconfig import get_python_inc; print(get_python_inc())") \
-DPYTHON2_PACKAGES_PATH=$(/opt/conda/envs/ocvpy2/bin/python -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())") \
-DPYTHON3_EXECUTABLE=/opt/conda/envs/ocvpy3/bin/python \
-DPYTHON3_INCLUDE_DIR=$(/opt/conda/envs/ocvpy3/bin/python -c "from distutils.sysconfig import get_python_inc; print(get_python_inc())") \
-DPYTHON3_PACKAGES_PATH=$(/opt/conda/envs/ocvpy3/bin/python -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())") \
-DOPENCV_EXTRA_MODULES_PATH=/opencv_contrib-${OPENCV_VERSION}/modules \
-DBUILD_opencv_legacy=OFF \
-DCMAKE_BUILD_TYPE=RELEASE \
-DCMAKE_INSTALL_PREFIX=/opencv-${OPENCV_VERSION}/install

WORKDIR /opencv-${OPENCV_VERSION}/build
RUN make -j $(nproc) install
WORKDIR /

# Example on how to build on the above dockerfile to launch Python 3.6 scripts that uses cv2
# SHELL ["/bin/bash", "-c", "source /opt/conda/envs/ocvpy3/bin/activate"]
# RUN python -c "import cv2; print(cv2.__file__)"
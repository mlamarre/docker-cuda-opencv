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
        pkg-config \
        libcurl4-openssl-dev \
        zlib1g-dev \
        nano
        
# Building a recent CMake to benefit from improvement in the CUDA workflow
ENV CMAKE_VERSION=3.10
ENV CMAKE_BUILD=2.1
RUN mkdir ~/temp && cd ~/temp && wget https://github.com/mlamarre/CMake/archive/v${CMAKE_VERSION}.${CMAKE_BUILD}.tar.gz -O cmake-${CMAKE_VERSION}.${CMAKE_BUILD}.tar.gz\
&& tar -xzvf cmake-${CMAKE_VERSION}.${CMAKE_BUILD}.tar.gz \
&& cd ~/temp/CMake-${CMAKE_VERSION}.${CMAKE_BUILD}/ && ./bootstrap --system-curl && make -j$(nproc) && make install && make clean && cd ~ && rm -rf temp 

WORKDIR /

# Getting OpenCV dependencies available with apt
RUN apt-get update && apt-get install -y \
        libswscale-dev \
        libtbb2 \
        libtbb-dev \
        libjpeg-dev \
        libpng-dev \
        libtiff-dev \
        libjasper-dev \
        libavformat-dev \
        libpq-dev \
        libhdf5-dev \
    && apt-get clean

# Using Miniconda to get Python 2.7.x and 3.6.y to get Numpy linked with Intel MKL for max performance
RUN echo 'export PATH=/opt/conda/bin:$PATH' > /etc/profile.d/conda.sh && \
    wget --quiet https://repo.continuum.io/miniconda/Miniconda3-4.3.31-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh

ENV PATH /opt/conda/bin:$PATH

# Create two conda env. just for the purpose of building 
RUN conda create -y -n ocvpy3 python=3.6.4 numpy=1.14.0 mkl-devel
RUN conda create -y -n ocvpy2 python=2.7.14 numpy=1.14.0 mkl-devel
# Copy Intel MKL to /usr/local/lib which is on ld search path on this container already
# Run ldconfig to refresh ld's cache and create links
RUN cp /opt/conda/envs/ocvpy3/include/mkl*.h /usr/local/include\
&& cp /opt/conda/envs/ocvpy3/lib/libmkl*.so /usr/local/lib && ldconfig -v

# Recent version of Eigen C++ - the folder inside the zip  is some kind of hash
ENV EIGEN_VERSION="3.3.4"
ENV EIGEN_SUBPATH="5a0156e40feb"
RUN mkdir /temp \ 
&& wget http://bitbucket.org/eigen/eigen/get/3.3.4.zip -O /temp/eigen-${EIGEN_VERSION}.zip \
&& unzip /temp/eigen-${EIGEN_VERSION}.zip \
&& cd /eigen-eigen-${EIGEN_SUBPATH}\
&& mkdir build\
&& cd build\
&& cmake .. \
-DCMAKE_INSTALL_PREFIX=/usr/local\
&& make install\
&& rm -rf /temp\
&& rm -rf /eigen-eigen-${EIGEN_SUBPATH}

WORKDIR /

ENV OPENCV_VERSION="3.4.0"

# Fetching OpenCV and OpenCV contrib sources
# Generate the makefile with CMake - note that IPP is downloaded at generation time
# Important: currently only builds sm_61 cuda architectures which means 
# GTX 1080, GTX 1070, GTX 1060, GTX 1050, GTX 1030, Titan Xp, Tesla P40, Tesla P4 and better
RUN mkdir /temp \ 
&& wget -nv https://github.com/opencv/opencv_contrib/archive/${OPENCV_VERSION}.zip -O /temp/opencvcontrib-${OPENCV_VERSION}.zip \
&& wget -nv https://github.com/opencv/opencv/archive/${OPENCV_VERSION}.zip -O /temp/opencv-${OPENCV_VERSION}.zip \
&& wget -nv https://github.com/VLAM3D/opencv-python/archive/9.1.zip -O /temp/opencv-python-9.1.zip \
&& unzip /temp/opencv-${OPENCV_VERSION}.zip\
&& unzip /temp/opencvcontrib-${OPENCV_VERSION}.zip\
&& unzip /temp/opencv-python-9.1.zip\
&& cd /opencv-${OPENCV_VERSION} && mkdir build && cd build && \
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
-DWITH_EIGEN=ON \
-DWITH_V4L=ON \
-DWITH_FFMPEG=ON \
-DBUILD_TESTS=OFF \
-DBUILD_PERF_TESTS=OFF \
-DPYTHON2_EXECUTABLE=/opt/conda/envs/ocvpy2/bin/python \
-DPYTHON2_INCLUDE_DIR=$(/opt/conda/envs/ocvpy2/bin/python -c "from distutils.sysconfig import get_python_inc; print(get_python_inc())") \
-DPYTHON2_PACKAGES_PATH=$(/opt/conda/envs/ocvpy2/bin/python -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())") \
-DPYTHON3_EXECUTABLE=/opt/conda/envs/ocvpy3/bin/python \
-DPYTHON3_INCLUDE_DIR=$(/opt/conda/envs/ocvpy3/bin/python -c "from distutils.sysconfig import get_python_inc; print(get_python_inc())") \
-DPYTHON3_PACKAGES_PATH=$(/opt/conda/envs/ocvpy3/bin/python -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())") \
-DOPENCV_EXTRA_MODULES_PATH=/opencv_contrib-${OPENCV_VERSION}/modules \
-DBUILD_opencv_legacy=OFF \
-DCMAKE_BUILD_TYPE=RELEASE \
-DCMAKE_INSTALL_PREFIX=/usr/local \
-DCMAKE_SKIP_BUILD_RPATH=BOOL:FALSE \
-CMAKE_BUILD_WITH_INSTALL_RPATH=BOOL:FALSE \
-CMAKE_INSTALL_RPATH="$ORIGIN/" \
-CMAKE_INSTALL_RPATH_USE_LINK_PATH=BOOL:TRUE \
&& cd /opencv-${OPENCV_VERSION}/build \
&& make -j $(nproc) install \
&& mkdir -p /usr/local/etc/wheels \
&& cd /opencv-python-9.1 \
&& python find_version.py \
&& cp /opt/conda/envs/ocvpy3/lib/python3.6/site-packages/cv2.cpython-36m-x86_64-linux-gnu.so /opencv-python-9.1/cv2/ \
&& /bin/bash -c "source /opt/conda/envs/ocvpy3/bin/activate ocvpy3 && python setup.py bdist_wheel" \
&& rm /opencv-python-9.1/cv2/cv2.cpython-36m-x86_64-linux-gnu.so \
&& cp /opt/conda/envs/ocvpy2/lib/python2.7/site-packages/cv2.so /opencv-python-9.1/cv2/ \
&& /bin/bash -c "source /opt/conda/envs/ocvpy2/bin/activate ocvpy2 && python setup.py bdist_wheel" \
&& cp /opencv-python-9.1/dist/opencv_python-*.whl /usr/local/etc/wheels \
&& cd / \
&& rm -rf /opencv-python-9.1 \
&& rm -rf /opencv-${OPENCV_VERSION} \
&& rm -rf /opencv_contrib-${OPENCV_VERSION} \
&& rm -rf /temp

RUN ldconfig -v

# Example on how to add on the above dockerfile to launch Python 3.6 scripts that uses cv2
# SHELL ["/bin/sh", "-c", "source /opt/conda/envs/ocvpy3/bin/activate"]
# RUN python -c "import cv2; print(cv2.__file__)"
# 
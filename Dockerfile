from ubuntu:18.04

# Install system tools
RUN apt-get update && \
    apt-get -y install libreadline6-dev libncurses5-dev perl build-essential \
                       vim wget git re2c && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV INSTALL_BASE_PATH /root/epics

RUN mkdir -p $INSTALL_BASE_PATH
RUN mkdir -p $INSTALL_BASE_PATH/base
RUN mkdir -p $INSTALL_BASE_PATH/modules
RUN mkdir -p $INSTALL_BASE_PATH/iocs

RUN mkdir -p /root/sandbox/epics
WORKDIR /root/sandbox/epics

ENV EPICS_BASE_VERSION R7.0.3.1

######################################
# Install EPICS base
######################################
RUN git clone --depth=1 --recursive --branch $EPICS_BASE_VERSION https://github.com/epics-base/epics-base.git
WORKDIR epics-base
RUN make -j8 install STATIC_BUILD=YES INSTALL_LOCATION=$INSTALL_BASE_PATH/base/ && \
    cp -r startup /root/epics/base/.

######################################
# Install the EPICS Modules
######################################
ENV EPICS_BASE_LOCATION $INSTALL_BASE_PATH/base
ENV MODULES_DIR $INSTALL_BASE_PATH/modules

ENV ASYN_VERSION master
ENV AUTOSAVE_VERSION master
ENV CALC_VERSION master
ENV BUSY_VERSION master
ENV MOTOR_VERSION master
ENV CAPUTLOG_VERSION master

# asyn
WORKDIR /root/sandbox/epics/modules
RUN git clone --depth=1 --recursive --branch $ASYN_VERSION https://github.com/epics-modules/asyn.git
WORKDIR asyn
RUN echo "EPICS_BASE=$EPICS_BASE_LOCATION" > configure/RELEASE
RUN make -j8 install STATIC_BUILD=YES INSTALL_LOCATION=$MODULES_DIR/asyn

# autosave
WORKDIR /root/sandbox/epics/modules
RUN git clone --depth=1 --recursive --branch $AUTOSAVE_VERSION https://github.com/epics-modules/autosave.git
WORKDIR autosave
RUN echo "EPICS_BASE=$EPICS_BASE_LOCATION" > configure/RELEASE
RUN make -j8 install STATIC_BUILD=YES INSTALL_LOCATION=$MODULES_DIR/autosave

# calc
WORKDIR /root/sandbox/epics/modules
RUN git clone --depth=1 --recursive --branch $CALC_VERSION https://github.com/epics-modules/calc.git
WORKDIR calc
RUN echo "EPICS_BASE=$EPICS_BASE_LOCATION" > configure/RELEASE
RUN make -j8 install STATIC_BUILD=YES INSTALL_LOCATION=$MODULES_DIR/calc

# busy
WORKDIR /root/sandbox/epics/modules
RUN git clone --depth=1 --recursive --branch $BUSY_VERSION https://github.com/epics-modules/busy.git
WORKDIR busy
RUN echo "ASYN=$MODULES_DIR/asyn\n\
EPICS_BASE=$EPICS_BASE_LOCATION" \
> configure/RELEASE
RUN make -j8 install STATIC_BUILD=YES INSTALL_LOCATION=$MODULES_DIR/busy

# seq
WORKDIR /root/sandbox/epics/modules
RUN wget http://www-csr.bessy.de/control/SoftDist/sequencer/releases/seq-2.2.8.tar.gz && tar -xzvf seq-2.2.8.tar.gz && mv seq-2.2.8 seq
WORKDIR seq
RUN echo "EPICS_BASE=$EPICS_BASE_LOCATION" > configure/RELEASE
RUN make -j8 install STATIC_BUILD=YES INSTALL_LOCATION=$MODULES_DIR/seq

# caPutLog
WORKDIR /root/sandbox/epics/modules
RUN git clone --depth=1 --recursive --branch $CAPUTLOG_VERSION https://github.com/epics-modules/caPutLog.git
WORKDIR caPutLog
RUN echo "EPICS_BASE=$EPICS_BASE_LOCATION" > configure/RELEASE
RUN make -j8 install STATIC_BUILD=YES INSTALL_LOCATION=$MODULES_DIR/caPutLog

# motor
WORKDIR /root/sandbox/epics/modules
RUN git clone --depth=1 --branch $MOTOR_VERSION https://github.com/epics-modules/motor.git
WORKDIR motor
RUN git submodule init
RUN git submodule update modules/motorMotorSim
RUN mv configure/EXAMPLE_CONFIG_SITE.local configure/CONFIG_SITE.local

RUN echo "BUSY=$MODULES_DIR/busy\n\
SNCSEQ=$MODULES_DIR/seq\n\
ASYN=$MODULES_DIR/asyn\n\
EPICS_BASE=$EPICS_BASE_LOCATION" \
> configure/RELEASE

RUN make install STATIC_BUILD=YES INSTALL_LOCATION=$MODULES_DIR/motor

ENV EPICS_HOST_ARCH linux-x86_64
RUN make -C modules/motorMotorSim/iocs/motorSimIOC/iocBoot/iocMotorSim
RUN mkdir -p $INSTALL_BASE_PATH/iocs/motor/

RUN cp -r modules/motorMotorSim/iocs/motorSimIOC/iocBoot/iocMotorSim $INSTALL_BASE_PATH/iocs/motor/.
WORKDIR $INSTALL_BASE_PATH/iocs/motor/iocMotorSim
RUN echo '\
epicsEnvSet("IOC","iocMotorSim") \n \
epicsEnvSet("TOP","/root/epics/modules/motor") \n \
epicsEnvSet("MOTOR","/root/epics/modules/motor") \n \
epicsEnvSet("ASYN","/root/epics/modules/asyn") \n \
epicsEnvSet("SNCSEQ","/root/epics/modules/seq") \n \
epicsEnvSet("BUSY","/root/epics/modules/busy") \n \
epicsEnvSet("EPICS_BASE","/root/epics/base")' \
> envPaths
RUN sed -i '11 c\cd "/root/epics/iocs/motor/${IOC}"' st.cmd


# areaDetector
WORKDIR /root/sandbox/epics/modules
ENV AREADETECTOR_VERSION master
RUN git clone --depth=1 --branch $AREADETECTOR_VERSION https://github.com/areaDetector/areaDetector.git
WORKDIR areaDetector
RUN git submodule update --init ADCore && \
 git submodule update --init ADSupport && \
 git submodule update --init ADSimDetector && \
 cd ADCore && git checkout master && \
 cd ../ADSupport && git checkout master && \
 cd ../ADSimDetector && git checkout master && \
 cd ../

COPY patches/epics_modules_config/areaDetector/configure ./configure

RUN cd ADSupport && \
 make install -j8 STATIC_BUILD=YES && \
 make install STATIC_BUILD=YES INSTALL_LOCATION=$MODULES_DIR/areaDetector/ADSupport

RUN cd ADCore && \
 make install -j8 STATIC_BUILD=YES && \
 make install STATIC_BUILD=YES INSTALL_LOCATION=$MODULES_DIR/areaDetector/ADCore

RUN cd ADSimDetector && \
 make install -j8 STATIC_BUILD=YES && \
 make install STATIC_BUILD=YES INSTALL_LOCATION=$MODULES_DIR/areaDetector/ADSimDetector

RUN mkdir -p $INSTALL_BASE_PATH/iocs/areaDetector
RUN cp -r ADSimDetector/iocs/simDetectorIOC/iocBoot/iocSimDetector $INSTALL_BASE_PATH/iocs/areaDetector/iocSimDetector
RUN mkdir -p $MODULES_DIR/areaDetector/ADCore/iocBoot/
RUN cp ADCore/iocBoot/EXAMPLE_commonPlugin_settings.req $MODULES_DIR/areaDetector/ADCore/iocBoot/commonPlugin_settings.req
RUN cp ADCore/iocBoot/EXAMPLE_commonPlugins.cmd $MODULES_DIR/areaDetector/ADCore/iocBoot/commonPlugins.cmd

COPY patches/epics_iocs_config/areaDetector /root/epics/iocs/areaDetector

# Copy over IOC Launching Scripts
COPY launchers $INSTALL_BASE_PATH/iocs/launchers

# Copy over IOC that links motor and Area Detector
COPY linker $INSTALL_BASE_PATH/iocs/linker

WORKDIR $INSTALL_BASE_PATH

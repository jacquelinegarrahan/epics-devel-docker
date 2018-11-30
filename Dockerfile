from ubuntu:18.04

# Install system tools
RUN apt-get update && \
    apt-get -y install libreadline6-dev libncurses5-dev perl build-essential \
                       vim wget git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV INSTALL_BASE_PATH /root/epics

RUN mkdir -p $INSTALL_BASE_PATH
RUN mkdir -p $INSTALL_BASE_PATH/base
RUN mkdir -p $INSTALL_BASE_PATH/modules
RUN mkdir -p $INSTALL_BASE_PATH/iocs

RUN mkdir -p /root/sandbox/epics
WORKDIR /root/sandbox/epics

ENV EPICS_BASE_VERSION R7.0.2-rc1

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

ENV ASYN_VERSION R4-34
ENV AUTOSAVE_VERSION R5-9
ENV CALC_VERSION master
ENV BUSY_VERSION master
ENV MOTOR_VERSION master

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

# motor
WORKDIR /root/sandbox/epics/modules
RUN git clone --depth=1 --recursive --branch $MOTOR_VERSION https://github.com/epics-modules/motor.git
WORKDIR motor
# Patch Makefile to also build the Sim Motor iocs
RUN sed -i 's/\#\!//g' Makefile
RUN echo "BUSY=$MODULES_DIR/busy\n\
ASYN=$MODULES_DIR/asyn\n\
EPICS_BASE=$EPICS_BASE_LOCATION" \
> configure/RELEASE
# Remove OMS from WithAsyn
RUN sed -i '/[Oo]ms/d' motorExApp/WithAsyn/Makefile
RUN make install STATIC_BUILD=YES INSTALL_LOCATION=$MODULES_DIR/motor
RUN mkdir $MODULES_DIR/motor/iocBoot
RUN echo "\n\
TOP = ../..\n\
include \$(TOP)/configure/CONFIG\n\
ARCH = linux-x86_64\n\
TARGETS += envPaths\n\
include \$(TOP)/configure/RULES.ioc\n\
" > iocBoot/iocSim/Makefile
RUN make -C iocBoot/iocSim
RUN echo '\n\
epicsEnvSet("IOC","iocSim")\n\
epicsEnvSet("TOP","/root/epics/modules/motor")\n\
epicsEnvSet("BUSY","/root/epics/modules/busy")\n\
epicsEnvSet("ASYN","/root/epics/modules/asyn")\n\
epicsEnvSet("EPICS_BASE","/root/epics/base")\n\
' > iocBoot/iocSim/envPaths
RUN sed -i 's/file \"..\/../file \"\$\(TOP\)/g' iocBoot/iocSim/motor.substitutions
RUN mkdir -p $INSTALL_BASE_PATH/iocs/motor/
RUN cp -r iocBoot/iocSim $INSTALL_BASE_PATH/iocs/motor/.

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
